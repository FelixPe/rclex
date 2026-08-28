defmodule Rclex.Client do
  @moduledoc false

  use GenServer, restart: :temporary

  require Logger

  alias Rclex.Nif

  def start_link(args) do
    service_type = Keyword.fetch!(args, :service_type)
    service_name = Keyword.fetch!(args, :service_name)
    name = Keyword.fetch!(args, :name)
    ns = Keyword.fetch!(args, :namespace)

    GenServer.start_link(__MODULE__, args, name: name(service_type, service_name, name, ns))
  end

  def name(service_type, service_name, name, namespace \\ "/") do
    {:global, {:client, service_type, service_name, name, namespace}}
  end

  def call_async(%request_type{} = request, service_name, name, namespace \\ "/") do
    service_type =
      String.to_existing_atom(String.trim_trailing(to_string(request_type), ".Request"))

    case GenServer.whereis(name(service_type, service_name, name, namespace)) do
      nil -> {:error, :not_found}
      pid -> GenServer.call(pid, {:call, request})
    end
  end

  @doc """
  Make a synchronous service call with a timeout in seconds. If the
  response is received within `timeout_sec` the tuple `{:ok, response}` is
  returned. If the timeout expires before a response arrives the pending
  request is removed and `{:error, :timeout}` is returned. The timeout value
  is a float number of seconds (can be `nil` for infinite wait).
  """
  @spec call_timeout(
          request :: struct(),
          service_name :: String.t(),
          node_name :: String.t(),
          namespace :: String.t(),
          timeout_sec :: float() | nil
        ) :: {:ok, struct()} | {:error, :timeout} | {:error, :not_found} | {:error, term()}
  def call_timeout(request, service_name, node_name, namespace \\ "/", timeout_sec \\ nil)
      when is_binary(service_name) and is_binary(node_name) do
    namespace = namespace || "/"

    service_type =
      String.to_existing_atom(String.trim_trailing(to_string(request.__struct__), ".Request"))

    case GenServer.whereis(name(service_type, service_name, node_name, namespace)) do
      nil ->
        {:error, :not_found}

      pid ->
        ref = make_ref()

        case GenServer.call(pid, {:call, request, {self(), ref}}) do
          {:ok, sequence} ->
            wait_for_response(pid, sequence, ref, timeout_sec)

          other ->
            other
        end
    end
  end

  defp wait_for_response(_pid, sequence, ref, nil) do
    receive do
      {:service_response, ^sequence, ^ref, response} -> {:ok, response}
    end
  end

  defp wait_for_response(pid, sequence, ref, timeout_sec) when is_number(timeout_sec) do
    timeout_ms = trunc(timeout_sec * 1000)

    receive do
      {:service_response, ^sequence, ^ref, response} -> {:ok, response}
    after
      timeout_ms ->
        # remove pending so memory does not leak
        GenServer.cast(pid, {:remove_pending, sequence})
        {:error, :timeout}
    end
  end

  def service_server_available?(service_type, service_name, name, namespace \\ "/") do
    case GenServer.whereis(name(service_type, service_name, name, namespace)) do
      nil -> {:error, :not_found}
      pid -> GenServer.call(pid, {:service_server_available})
    end
  end

  @doc """
  Reconfigure client introspection at runtime, switching between `:off`, `:metadata` and `:contents`.
  """
  def configure_introspection(
        service_type,
        service_name,
        name,
        introspection,
        introspection_qos \\ Rclex.QoS.profile_services_default(),
        namespace \\ "/"
      )
      when introspection in [:off, :metadata, :contents] do
    case GenServer.whereis(name(service_type, service_name, name, namespace)) do
      nil -> {:error, :not_found}
      pid -> GenServer.call(pid, {:configure_introspection, introspection, introspection_qos})
    end
  end

  # callbacks

  def init(args) do
    Process.flag(:trap_exit, true)

    context = Keyword.fetch!(args, :context)
    node = Keyword.fetch!(args, :node)
    service_type = Keyword.fetch!(args, :service_type)
    service_name = Keyword.fetch!(args, :service_name)
    name = Keyword.fetch!(args, :name)
    namespace = Keyword.fetch!(args, :namespace)
    callback = Keyword.fetch!(args, :callback)
    qos = Keyword.get(args, :qos, Rclex.QoS.profile_services_default())
    introspection = Keyword.get(args, :introspection, :off)

    introspection_qos =
      Keyword.get(args, :introspection_qos, Rclex.QoS.profile_services_default())

    type_support = apply(service_type, :type_support!, [])
    client = Nif.rcl_client_init!(node, type_support, ~c"#{service_name}", qos)

    introspection_clock =
      start_introspection(client, node, service_type, introspection, introspection_qos)

    {:ok,
     %{
       node: node,
       context: context,
       client: client,
       callback: callback,
       service_type: service_type,
       service_name: service_name,
       name: name,
       namespace: namespace,
       request_type: apply(service_type, :request_type, []),
       response_type: apply(service_type, :response_type, []),
       callback_resource: nil,
       requests: %{},
       introspection_clock: introspection_clock
     }, {:continue, nil}}
  end

  def terminate(
        reason,
        %{
          node: node,
          client: client,
          callback_resource: callback_resource,
          introspection_clock: introspection_clock
        } = state
      ) do
    Nif.rcl_client_clear_response_callback!(client, callback_resource)
    Nif.rcl_client_fini!(client, node)

    if introspection_clock do
      Nif.rcl_clock_fini!(introspection_clock)
    end

    Logger.debug("#{__MODULE__}: #{inspect(reason)} #{Path.join(state.namespace, state.name)}")
  end

  def handle_continue(nil, %{client: client} = state) do
    callback_resource = Nif.rcl_client_set_on_new_response_callback!(client)
    {:noreply, %{state | callback_resource: callback_resource}}
  end

  def handle_call(
        {:configure_introspection, introspection, introspection_qos},
        _from,
        %{
          client: client,
          node: node,
          service_type: service_type,
          introspection_clock: introspection_clock
        } = state
      ) do
    new_introspection_clock =
      reconfigure_introspection(
        client,
        node,
        service_type,
        introspection_clock,
        introspection,
        introspection_qos
      )

    {:reply, :ok, %{state | introspection_clock: new_introspection_clock}}
  end

  def handle_call(
        {:call, request_struct},
        _from,
        %{
          client: client,
          request_type: request_type,
          requests: requests
        } = state
      ) do
    request_message = apply(request_type, :create!, [])

    {:ok, sequence_number} =
      try do
        :ok = apply(request_type, :set!, [request_message, request_struct])
        Nif.rcl_send_request!(client, request_message)
      after
        :ok = apply(request_type, :destroy!, [request_message])
      end

    requests = Map.put_new(requests, sequence_number, request_struct)
    {:reply, :ok, Map.put(state, :requests, requests)}
  end

  def handle_call(
        {:call, request_struct, {caller, ref}},
        _from,
        %{
          client: client,
          request_type: request_type,
          requests: requests
        } = state
      ) do
    request_message = apply(request_type, :create!, [])

    {:ok, sequence_number} =
      try do
        :ok = apply(request_type, :set!, [request_message, request_struct])
        Nif.rcl_send_request!(client, request_message)
      after
        :ok = apply(request_type, :destroy!, [request_message])
      end

    requests = Map.put_new(requests, sequence_number, {request_struct, {caller, ref}})
    {:reply, {:ok, sequence_number}, Map.put(state, :requests, requests)}
  end

  def handle_call(
        {:service_server_available},
        _from,
        %{
          node: node,
          client: client
        } = state
      ) do
    is_available = Nif.rcl_service_server_is_available!(node, client)
    {:reply, is_available, state}
  end

  def handle_info(
        {:new_response, number_of_events},
        %{
          client: client,
          callback: callback,
          response_type: response_type,
          requests: requests
        } = state
      )
      when number_of_events > 0 do
    requests =
      Enum.reduce(1..number_of_events, requests, fn _i, requests ->
        response_message = apply(response_type, :create!, [])

        try do
          case Nif.rcl_take_response_with_info!(client, response_message) do
            {:ok, response_sequence_number} ->
              response_struct = apply(response_type, :get!, [response_message])

              {entry, requests} = Map.pop(requests, response_sequence_number)

              case entry do
                {_req_struct, {caller, ref}} when is_pid(caller) ->
                  # synchronous caller waiting for reply
                  send(
                    caller,
                    {:service_response, response_sequence_number, ref, response_struct}
                  )

                request_struct when is_map(request_struct) and not is_tuple(request_struct) ->
                  # legacy asynchronous callback style
                  {:ok, _pid} =
                    Task.Supervisor.start_child(
                      {:via, PartitionSupervisor, {Rclex.TaskSupervisors, self()}},
                      fn ->
                        callback.(request_struct, response_struct)
                      end
                    )

                _ ->
                  :ok
              end

              requests

            :client_take_failed ->
              Logger.debug(
                "Client on node #{state.namespace}#{state.name} found no response to take from service #{state.service_name}."
              )

              requests
          end
        after
          :ok = apply(response_type, :destroy!, [response_message])
        end
      end)

    {:noreply, Map.put(state, :requests, requests)}
  end

  def handle_cast({:remove_pending, sequence}, %{requests: requests} = state) do
    {:noreply, %{state | requests: Map.delete(requests, sequence)}}
  end

  defp start_introspection(_client, _node, _client_type, :off, _qos), do: nil

  defp start_introspection(client, node, client_type, state, qos)
       when state in [:metadata, :contents] do
    clock = Nif.rcl_clock_init!(:ros_time)

    try do
      type_support = apply(client_type, :type_support!, [])

      :ok =
        Nif.rcl_client_configure_service_introspection!(
          client,
          node,
          clock,
          type_support,
          qos,
          state
        )

      clock
    rescue
      exception ->
        Nif.rcl_clock_fini!(clock)
        reraise exception, __STACKTRACE__
    end
  end

  # already off, nothing to tear down
  defp reconfigure_introspection(_client, _node, _client_type, nil, :off, _qos), do: nil

  # first time enabling, no existing clock to reuse
  defp reconfigure_introspection(client, node, client_type, nil, state, qos)
       when state in [:metadata, :contents] do
    start_introspection(client, node, client_type, state, qos)
  end

  # disabling requires passing the existing clock so rcl can tear down the publisher
  defp reconfigure_introspection(client, node, client_type, clock, :off, qos) do
    type_support = apply(client_type, :type_support!, [])

    :ok =
      Nif.rcl_client_configure_service_introspection!(
        client,
        node,
        clock,
        type_support,
        qos,
        :off
      )

    Nif.rcl_clock_fini!(clock)
    nil
  end

  # switching between metadata/contents while enabled, reuse the existing clock
  defp reconfigure_introspection(client, node, client_type, clock, state, qos)
       when state in [:metadata, :contents] do
    type_support = apply(client_type, :type_support!, [])

    :ok =
      Nif.rcl_client_configure_service_introspection!(
        client,
        node,
        clock,
        type_support,
        qos,
        state
      )

    clock
  end
end
