defmodule Rclex.ActionServer do
  @moduledoc false

  use GenServer, restart: :temporary

  require Logger

  alias Rclex.Nif

  def start_link(args) do
    action_type = Keyword.fetch!(args, :action_type)
    action_name = Keyword.fetch!(args, :action_name)
    name = Keyword.fetch!(args, :name)
    ns = Keyword.fetch!(args, :namespace)

    GenServer.start_link(__MODULE__, args, name: name(action_type, action_name, name, ns))
  end

  def name(action_type, action_name, name, namespace \\ "/") do
    {:global, {:action_server, action_type, action_name, name, namespace}}
  end

  # callbacks

  def init(args) do
    Process.flag(:trap_exit, true)

    context = Keyword.fetch!(args, :context)
    node = Keyword.fetch!(args, :node)
    action_type = Keyword.fetch!(args, :action_type)
    action_name = Keyword.fetch!(args, :action_name)
    name = Keyword.fetch!(args, :name)
    namespace = Keyword.fetch!(args, :namespace)
    execute_callback = Keyword.fetch!(args, :execute_callback)
    goal_callback = Keyword.fetch!(args, :goal_callback)
    handle_accepted_callback = Keyword.get(args, :handle_accepted_callback, fn _req -> true end)
    cancel_callback = Keyword.get(args, :cancel_callback, fn _req -> false end)
    clock_type = Keyword.get(args, :clock_type, :steady_time)
    clock = Nif.rcl_clock_init!(clock_type)

    goal_service_qos = Keyword.get(args, :goal_service_qos, Rclex.QoS.profile_services_default())

    result_service_qos =
      Keyword.get(args, :result_service_qos, Rclex.QoS.profile_services_default())

    cancel_service_qos =
      Keyword.get(args, :cancel_service_qos, Rclex.QoS.profile_services_default())

    feedback_topic_qos = Keyword.get(args, :feedback_topic_qos, Rclex.QoS.profile_default())
    status_topic_qos = Keyword.get(args, :status_topic_qos, Rclex.QoS.profile_status_default())
    result_timeout = Keyword.get(args, :result_timeout, 10.0)

    1 = :erlang.fun_info(execute_callback)[:arity]
    1 = :erlang.fun_info(goal_callback)[:arity]
    1 = :erlang.fun_info(handle_accepted_callback)[:arity]
    1 = :erlang.fun_info(cancel_callback)[:arity]

    type_support = apply(action_type, :type_support!, [])

    action_server =
      Nif.rcl_action_server_init!(
        node,
        type_support,
        ~c"#{action_name}",
        clock,
        goal_service_qos,
        result_service_qos,
        cancel_service_qos,
        feedback_topic_qos,
        status_topic_qos,
        result_timeout
      )

    {:ok,
     %{
       node: node,
       context: context,
       action_server: action_server,
       action_type: action_type,
       action_name: action_name,
       clock: clock,
       execute_callback: execute_callback,
       goal_callback: goal_callback,
       handle_accepted_callback: handle_accepted_callback,
       cancel_callback: cancel_callback,
       name: name,
       namespace: namespace,
       cancel_service_callback_resource: nil,
       goal_service_callback_resource: nil,
       result_service_callback_resource: nil
     }, {:continue, nil}}
  end

  def terminate(
        reason,
        %{
          node: node,
          action_server: action_server,
          clock: clock,
          cancel_service_callback_resource: cancel_service_cr,
          goal_service_callback_resource: goal_service_cr,
          result_service_callback_resource: result_service_cr
        } = state
      ) do
    Nif.rcl_action_server_clear_cancel_service_callback!(action_server, cancel_service_cr)
    Nif.rcl_action_server_clear_goal_service_callback!(action_server, goal_service_cr)
    Nif.rcl_action_server_clear_result_service_callback!(action_server, result_service_cr)
    Nif.rcl_action_server_fini!(action_server, node)
    Nif.rcl_clock_fini!(clock)

    Logger.debug("#{__MODULE__}: #{inspect(reason)} #{Path.join(state.namespace, state.name)}")
  end

  def handle_continue(nil, %{action_server: action_server} = state) do
    goal_service_cr = Nif.rcl_action_server_set_goal_service_callback!(action_server)
    cancel_service_cr = Nif.rcl_action_server_set_cancel_service_callback!(action_server)
    result_service_cr = Nif.rcl_action_server_set_result_service_callback!(action_server)

    {:noreply,
     %{
       state
       | cancel_service_callback_resource: cancel_service_cr,
         goal_service_callback_resource: goal_service_cr,
         result_service_callback_resource: result_service_cr
     }}
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

                  apply(response_type, :set!, [
                    response_message,
                    response_message_struct
                  ])

                  :ok = Nif.rcl_send_response!(service, request_header, response_message)
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
end
