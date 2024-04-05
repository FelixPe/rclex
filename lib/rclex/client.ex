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
      String.to_existing_atom(String.trim_trailing(to_string(request_type), "Request"))

    case GenServer.whereis(name(service_type, service_name, name, namespace)) do
      nil -> {:error, :not_found}
      {_atom, _node} -> raise("should not happen")
      pid -> GenServer.call(pid, {:call, request})
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

    type_support = apply(service_type, :type_support!, [])
    client = Nif.rcl_client_init!(node, type_support, ~c"#{service_name}", qos)
    wait_set = Nif.rcl_wait_set_init_client!(context)

    {:ok,
     %{
       node: node,
       client: client,
       callback: callback,
       service_type: service_type,
       service_name: service_name,
       name: name,
       namespace: namespace,
       wait_set: wait_set,
       request_type: apply(service_type, :request_type, []),
       response_type: apply(service_type, :response_type, []),
       requests: %{}
     }}
  end

  def terminate(reason, state) do
    Nif.rcl_wait_set_fini!(state.wait_set)
    Nif.rcl_client_fini!(state.client, state.node)

    Logger.debug("#{__MODULE__}: #{inspect(reason)} #{Path.join(state.namespace, state.name)}")
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

    send(self(), :take_response)

    requests = Map.put_new(requests, sequence_number, request_struct)
    {:reply, :ok, Map.put(state, :requests, requests)}
  end

  def handle_info(
        :take_response,
        %{
          client: client,
          callback: callback,
          response_type: response_type,
          wait_set: wait_set,
          requests: requests
        } = state
      ) do
    case Nif.rcl_wait_client!(wait_set, 1000, client) do
      :ok ->
        response_message = apply(response_type, :create!, [])

        try do
          {:ok, response_sequence_number} =
            Nif.rcl_take_response_with_info!(client, response_message)

          response_struct = apply(response_type, :get!, [response_message])

          {request_struct, requests} = Map.pop(requests, response_sequence_number)

          if request_struct do
            {:ok, _pid} =
              Task.Supervisor.start_child(
                {:via, PartitionSupervisor, {Rclex.TaskSupervisors, self()}},
                fn ->
                  callback.(request_struct, response_struct)
                end
              )
          end

          {:noreply, Map.put(state, :requests, requests)}
        after
          :ok = apply(response_type, :destroy!, [response_message])
        end

      :timeout ->
        send(self(), :take_response)
        {:noreply, state}
    end
  end
end
