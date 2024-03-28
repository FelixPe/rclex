defmodule Rclex.Service do
  @moduledoc false

  use GenServer, restart: :temporary

  require Logger

  alias Rclex.Nif


  def start_link(args) do
    service_type = Keyword.fetch!(args, :service_type)
    service_name = Keyword.fetch!(args, :service_name)
    name = Keyword.fetch!(args, :name)
    namespace = Keyword.fetch!(args, :namespace)

    GenServer.start_link(__MODULE__, args, name: name(service_type, service_name, name, namespace))
  end

  def name(service_type, service_name, name, namespace \\ "/") do
    {:global, {:service, service_type, service_name, name, namespace}}
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

    1 = :erlang.fun_info(callback)[:arity]

    type_support = apply(service_type, :type_support!, [])
    service = Nif.rcl_service_init!(node, type_support, ~c"#{service_name}", qos)
    wait_set = Nif.rcl_wait_set_init_service!(context)

    send(self(), :take_request)

    {:ok,
     %{
       node: node,
       service: service,
       service_type: service_type,
       service_name: service_name,
       callback: callback,
       name: name,
       namespace: namespace,
       wait_set: wait_set,
       request_type: apply(service_type, :request_type, []),
       response_type: apply(service_type, :response_type, [])
     }}
  end

  def terminate(reason, state) do
    Nif.rcl_wait_set_fini!(state.wait_set)
    Nif.rcl_service_fini!(state.service, state.node)

    Logger.debug("#{__MODULE__}: #{inspect(reason)} #{Path.join(state.namespace, state.name)}")
  end

  def handle_info(:take_request, state) do
    case Nif.rcl_wait_service!(state.wait_set, 1000, state.service) do
      :ok ->
        request_message = apply(state.request_type, :create!, [])

        try do
          case Nif.rcl_take_request_with_info!(state.service, request_message) do
            {:ok, request_header} ->
              request_message_struct = apply(state.request_type, :get!, [request_message])

              {:ok, _pid} =
                Task.Supervisor.start_child(
                  {:via, PartitionSupervisor, {Rclex.TaskSupervisors, self()}},
                  fn -> 
                    response_message_struct = state.callback.(request_message_struct)
                    response_message = apply(state.response_type, :create!, [])
                    apply(state.response_type, :set!, [response_message, response_message_struct])
                    Nif.rcl_send_response!(state.service, request_header, response_message)
                  end
                )

            :error ->
              Logger.error("#{__MODULE__}: take failed but no error occurred in the middleware")
          end
        after
          :ok = apply(state.request_type, :destroy!, [request_message])
        end

      :timeout ->
        nil
    end

    send(self(), :take_request)

    {:noreply, state}
  end
end
