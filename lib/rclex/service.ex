defmodule Rclex.Service do
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
    {:global, {:service, service_type, service_name, name, namespace}}
  end

  @doc """
  Reconfigure service introspection at runtime, switching between `:off`, `:metadata` and `:contents`.
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

    1 = :erlang.fun_info(callback)[:arity]

    type_support = apply(service_type, :type_support!, [])
    service = Nif.rcl_service_init!(node, type_support, ~c"#{service_name}", qos)

    introspection_clock =
      start_introspection(service, node, service_type, introspection, introspection_qos)

    {:ok,
     %{
       node: node,
       context: context,
       service: service,
       service_type: service_type,
       service_name: service_name,
       callback: callback,
       name: name,
       namespace: namespace,
       request_type: apply(service_type, :request_type, []),
       response_type: apply(service_type, :response_type, []),
       introspection_clock: introspection_clock,
       callback_resource: nil
     }, {:continue, nil}}
  end

  def terminate(
        reason,
        %{
          node: node,
          service: service,
          callback_resource: callback_resource,
          introspection_clock: introspection_clock
        } = state
      ) do
    Nif.rcl_service_clear_request_callback!(service, callback_resource)
    Nif.rcl_service_fini!(service, node)

    if introspection_clock do
      Nif.rcl_clock_fini!(introspection_clock)
    end

    Logger.debug("#{__MODULE__}: #{inspect(reason)} #{Path.join(state.namespace, state.name)}")
  end

  def handle_continue(nil, %{service: service} = state) do
    callback_resource = Nif.rcl_service_set_on_new_request_callback!(service)
    {:noreply, %{state | callback_resource: callback_resource}}
  end

  def handle_call(
        {:configure_introspection, introspection, introspection_qos},
        _from,
        %{
          service: service,
          node: node,
          service_type: service_type,
          introspection_clock: introspection_clock
        } = state
      ) do
    new_introspection_clock =
      reconfigure_introspection(
        service,
        node,
        service_type,
        introspection_clock,
        introspection,
        introspection_qos
      )

    {:reply, :ok, %{state | introspection_clock: new_introspection_clock}}
  end

  def handle_info(
        {:new_request, number_of_events},
        %{
          service: service,
          request_type: request_type,
          response_type: response_type,
          callback: callback
        } = state
      )
      when number_of_events > 0 do
    for _ <- 1..number_of_events do
      request_message = apply(request_type, :create!, [])

      try do
        case Nif.rcl_take_request_with_info!(service, request_message) do
          {:ok, request_header} ->
            request_message_struct = apply(request_type, :get!, [request_message])

            {:ok, _pid} =
              Task.Supervisor.start_child(
                {:via, PartitionSupervisor, {Rclex.TaskSupervisors, self()}},
                fn ->
                  response_message_struct = callback.(request_message_struct)
                  response_message = apply(response_type, :create!, [])

                  try do
                    :ok =
                      apply(response_type, :set!, [
                        response_message,
                        response_message_struct
                      ])

                    :ok = Nif.rcl_send_response!(service, request_header, response_message)
                  after
                    :ok = apply(response_type, :destroy!, [response_message])
                  end
                end
              )

          :service_take_failed ->
            Logger.debug("#{__MODULE__}: take failed but no error occurred in the middleware")
        end
      after
        :ok = apply(request_type, :destroy!, [request_message])
      end
    end

    {:noreply, state}
  end

  defp start_introspection(_service, _node, _service_type, :off, _qos), do: nil

  defp start_introspection(service, node, service_type, state, qos)
       when state in [:metadata, :contents] do
    clock = Nif.rcl_clock_init!(:ros_time)

    try do
      type_support = apply(service_type, :type_support!, [])

      :ok =
        Nif.rcl_service_configure_service_introspection!(
          service,
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
  defp reconfigure_introspection(_service, _node, _service_type, nil, :off, _qos), do: nil

  # first time enabling, no existing clock to reuse
  defp reconfigure_introspection(service, node, service_type, nil, state, qos)
       when state in [:metadata, :contents] do
    start_introspection(service, node, service_type, state, qos)
  end

  # disabling requires passing the existing clock so rcl can tear down the publisher
  defp reconfigure_introspection(service, node, service_type, clock, :off, qos) do
    type_support = apply(service_type, :type_support!, [])

    :ok =
      Nif.rcl_service_configure_service_introspection!(
        service,
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
  defp reconfigure_introspection(service, node, service_type, clock, state, qos)
       when state in [:metadata, :contents] do
    type_support = apply(service_type, :type_support!, [])

    :ok =
      Nif.rcl_service_configure_service_introspection!(
        service,
        node,
        clock,
        type_support,
        qos,
        state
      )

    clock
  end
end
