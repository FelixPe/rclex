defmodule Rclex.ActionServer do
  @moduledoc false

  use GenServer, restart: :temporary

  require Logger

  alias Rclex.Pkgs.ActionMsgs.Msg.GoalInfo
  alias Rclex.ActionServer.GoalHandle
  alias Rclex.Nif
  alias Rclex.ActionServer.GoalSupervisor

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

  def publish_status(goal_status, action_type, action_name, name, namespace \\ "/") do
    case GenServer.whereis(name(action_type, action_name, name, namespace)) do
      nil -> {:error, :not_found}
      {_atom, _node} -> raise("should not happen")
      pid -> GenServer.call(pid, {:publish_status, goal_status})
    end
  end

  def publish_feedback(feedback, action_type, action_name, name, namespace \\ "/") do
    case GenServer.whereis(name(action_type, action_name, name, namespace)) do
      nil -> {:error, :not_found}
      {_atom, _node} -> raise("should not happen")
      pid -> GenServer.call(pid, {:publish_feedback, feedback})
    end
  end

  def set_result(result, goal_id, action_type, action_name, name, namespace \\ "/") do
    case GenServer.whereis(name(action_type, action_name, name, namespace)) do
      nil -> {:error, :not_found}
      {_atom, _node} -> raise("should not happen")
      pid -> GenServer.call(pid, {:set_result, result, goal_id})
    end
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

    handle_accepted_callback =
      Keyword.get(args, :handle_accepted_callback, fn action_server, goal_info ->
        GoalHandle.execute_goal(action_server, goal_info)
      end)

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
    2 = :erlang.fun_info(handle_accepted_callback)[:arity]
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
       result_service_callback_resource: nil,
       goals: %{}
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

  def handle_cast({:publish_status, goal_status_struct}, %{action_server: action_server} = state) do
    message_type = Rclex.Pkgs.ActionMsgs.Msg.GoalStatus
    message = apply(message_type, :create!, [])

    try do
      :ok =
        apply(message_type, :set!, [
          message,
          goal_status_struct
        ])

      :ok = Nif.rcl_action_publish_status!(action_server, message)
    after
      :ok = apply(message_type, :destroy!, [message])
    end

    {:noreply, state}
  end

  def handle_cast(
        {:expire_goals, expired_goals},
        %{
          action_server: action_server,
          goals: goals
        } = state
      ) do
    expired_uuids =
      Nif.rcl_action_expire_goals!(action_server, expired_goals)
      |> Enum.map(fn goal_info_msg ->
        goal_info_struct = apply(GoalInfo, :get!, [goal_info_msg])
        apply(GoalInfo, :destroy!, [goal_info_msg])
        goal_info_struct
      end)

    remaining_goals = Map.drop(goals, expired_uuids)
    {:noreply, %{state | goals: remaining_goals}}
  end

  def handle_info(
        {:new_goal_request, number_of_events},
        %{
          action_name: action_name,
          name: name,
          namespace: namespace,
          action_server: action_server,
          action_type: action_type,
          goal_callback: goal_callback,
          execute_callback: execute_callback,
          handle_accepted_callback: handle_accepted_callback,
          clock: clock,
          goals: goals
        } = state
      )
      when number_of_events > 0 do
    goal_list =
      for _ <- 1..number_of_events do
        request_type = apply(action_type, :send_goal_request_type, [])
        response_type = apply(action_type, :send_goal_response_type, [])
        request_message = apply(request_type, :create!, [])

        try do
          case Nif.rcl_action_take_goal_request!(action_server, request_message) do
            {:ok, request_header} ->
              request_message_struct = apply(request_type, :get!, [request_message])
              goal_id = Map.fetch!(request_message_struct, :goal_id)
              goal = Map.fetch!(request_message_struct, :goal)

              goal_info_struct = gen_goal_info_struct(goal_id)

              goal_info_msg = apply(GoalInfo, :create!, [])

              try do
                :ok = apply(GoalInfo, :set!, [goal_info_msg, goal_info_struct])

                if Nif.rcl_action_server_goal_exists!(action_server, goal_info_msg) do
                  raise "goal id exists"
                end
              after
                :ok = apply(GoalInfo, :destroy!, [goal_info_msg])
              end

              accepted = goal_callback.(goal) == :accept
              time = now(clock)

              goal_info_struct = gen_goal_info_struct(goal_id, time)

              if accepted do
                {:ok, _pid} =
                  GoalSupervisor.start_goal(
                    goal_info_struct,
                    goal,
                    execute_callback,
                    handle_accepted_callback,
                    action_server,
                    action_type,
                    action_name,
                    name,
                    namespace
                  )
              end

              response_message_struct =
                gen_goal_response_struct(response_type, accepted, time)

              response_message = apply(response_type, :create!, [])

              try do
                :ok =
                  apply(response_type, :set!, [
                    response_message,
                    response_message_struct
                  ])

                :ok =
                  Nif.rcl_action_send_goal_response!(
                    action_server,
                    request_header,
                    response_message
                  )
              rescue
                # client is gone...we need to survive this
                e -> dbg(e)
              after
                :ok = apply(response_type, :destroy!, [response_message])
              end

              if accepted do
                Logger.debug(
                  "#{__MODULE__}: Goal [#{Base.encode16(goal_id.uuid)}] accepted: #{inspect(goal)}"
                )

                Task.Supervisor.start_child(
                  {:via, PartitionSupervisor, {Rclex.TaskSupervisors, self()}},
                  fn ->
                    handle_accepted_callback.(action_server, goal_info_struct)
                  end
                )

                {goal_id.uuid,
                 %{
                   goal: goal,
                   goal_info: goal_info_struct
                 }}
              else
                Logger.debug(
                  "#{__MODULE__}: Goal [#{Base.encode16(goal_id.uuid)}] rejected: #{inspect(goal)}"
                )

                nil
              end

            :action_server_take_failed ->
              Logger.debug("#{__MODULE__}: take failed but no error occurred in the middleware")
              nil
          end
        after
          :ok = apply(request_type, :destroy!, [request_message])
        end
      end

    goals =
      goal_list
      |> Enum.reject(&is_nil/1)
      |> Enum.into(goals)

    {:noreply, %{state | goals: goals}}
  end

  def handle_info(
        {:new_cancel_request, number_of_events},
        %{
          action_server: action_server,
          goals: goals,
          cancel_callback: cancel_callback
        } = state
      )
      when number_of_events > 0 do
    for _ <- 1..number_of_events do
      request_type = Rclex.Pkgs.ActionMsgs.Srv.CancelGoalRequest
      response_type = Rclex.Pkgs.ActionMsgs.Srv.CancelGoalResponse

      request_message = apply(request_type, :create!, [])

      try do
        case Nif.rcl_action_take_cancel_request!(action_server, request_message) do
          {:ok, request_header} ->
            # request_message_struct = apply(request_type, :get!, [request_message])

            response_message = apply(response_type, :create!, [])

            try do
              :ok =
                Nif.rcl_action_process_cancel_request!(
                  action_server,
                  request_message,
                  response_message
                )

              response_message_struct = apply(response_type, :get!, [response_message])

              for goal_info_struct <- response_message_struct.goals_canceling do
                uuid = goal_info_struct.goal_id.uuid

                case Map.fetch(goals, uuid) do
                  {:ok, %{goal_info: goal_info}} ->
                    accepted = cancel_callback.(goal_info) == :accept

                    if accepted do
                      GoalHandle.cancel_goal(action_server, goal_info)
                    end

                  :error ->
                    nil
                end
              end

              # :ok =
              #  apply(response_type, :set!, [
              #    response_message,
              #    response_message_struct
              #  ])

              :ok =
                Nif.rcl_action_send_cancel_response!(
                  action_server,
                  request_header,
                  response_message
                )
            rescue
              e -> dbg(e)
            after
              :ok = apply(response_type, :destroy!, [response_message])
            end

          :action_server_take_failed ->
            Logger.debug("#{__MODULE__}: take failed but no error occurred in the middleware")
        end
      after
        :ok = apply(request_type, :destroy!, [request_message])
      end
    end

    {:noreply, state}
  end

  def handle_info(
        {:new_result_request, number_of_events},
        %{
          action_server: action_server,
          action_type: action_type,
          goals: goals
        } = state
      )
      when number_of_events > 0 do
    for _ <- 1..number_of_events do
      request_type = apply(action_type, :send_goal_request_type, [])
      response_type = apply(action_type, :get_result_response_type, [])
      result_type = apply(action_type, :result_type, [])

      request_message = apply(request_type, :create!, [])

      try do
        case Nif.rcl_action_take_result_request!(action_server, request_message) do
          {:ok, request_header} ->
            request_message_struct = apply(request_type, :get!, [request_message])
            goal_id = Map.fetch!(request_message_struct, :goal_id)
            Logger.debug("Result request for Goal [#{Base.encode16(goal_id.uuid)}] received.")

            response_message_struct =
              case Map.fetch(goals, goal_id.uuid) do
                {:ok, goal} ->
                  if goal.result do
                    gen_result_response_struct(
                      response_type,
                      :status_succeeded,
                      goal.result
                    )
                  else
                    Logger.debug("#{inspect(request_header)} wait for result")
                  end

                :error ->
                  Logger.debug(
                    "Goal [#{Base.encode16(goal_id.uuid)}] in result request is unknown."
                  )

                  gen_result_response_struct(
                    response_type,
                    :status_unknown,
                    struct(result_type)
                  )
              end

            # There is an accepted goal matching the goal ID, register a callback to send the
            # response as soon as it's ready
            #                  self._result_futures[bytes(goal_uuid)].add_done_callback(
            #                      functools.partial(self._send_result_response, request_header))

            response_message = apply(response_type, :create!, [])

            try do
              :ok =
                apply(response_type, :set!, [
                  response_message,
                  response_message_struct
                ])

              :ok =
                Nif.rcl_action_send_result_response!(
                  action_server,
                  request_header,
                  response_message
                )
            after
              :ok = apply(response_type, :destroy!, [response_message])
            end

          :action_server_take_failed ->
            Logger.debug("#{__MODULE__}: take failed but no error occurred in the middleware")
        end
      after
        :ok = apply(request_type, :destroy!, [request_message])
      end
    end

    {:noreply, state}
  end

  defp now(clock) do
    Nif.rcl_clock_get_now!(clock)
  end

  defp gen_result_response_struct(response_type, status, result)
       when is_atom(response_type) and is_atom(status) and is_map(result) do
    status = apply(Rclex.Pkgs.ActionMsgs.Msg.GoalStatus, status, [])
    response_struct = struct(response_type)
    %{response_struct | :status => status, :result => result}
  end

  defp gen_time_struct(time_ns) do
    time_struct = struct(Rclex.Pkgs.BuiltinInterfaces.Msg.Time)
    %{time_struct | sec: div(time_ns, 1_000_000_000), nanosec: rem(time_ns, 1_000_000_000)}
  end

  defp gen_goal_response_struct(response_type, accepted, time) do
    time_struct = gen_time_struct(time)
    response_struct = struct(response_type)
    %{response_struct | accepted: accepted, stamp: time_struct}
  end

  #defp gen_goal_status_struct(goal_info, status) do
  #  goal_status_struct = struct(Rclex.Pkgs.ActionMsgs.Msg.GoalStatus)
  #  %{goal_status_struct | goal_info: goal_info, status: status}
  #end

  defp gen_goal_info_struct(goal_id) do
    goal_info_struct = struct(Rclex.Pkgs.ActionMsgs.Msg.GoalInfo)
    %{goal_info_struct | goal_id: goal_id}
  end

  defp gen_goal_info_struct(goal_id, time_ns) do
    goal_info_struct = struct(Rclex.Pkgs.ActionMsgs.Msg.GoalInfo)
    %{goal_info_struct | goal_id: goal_id, stamp: gen_time_struct(time_ns)}
  end

  #defp gen_feedback_message_struct(feedback_message_type, goal_id, feedback) do
  #  feedback_message_struct = struct(feedback_message_type)
  #  %{feedback_message_struct | goal_id: goal_id, feedback: feedback}
  #end

  #defp gen_cancel_goal_response_struct(return_code_atom, goals_canceling) do
  #  cancel_goal_response_struct = struct(Rclex.Pkgs.ActionMsgs.Srv.CancelGoalResponse)
  #  return_code = apply(Rclex.Pkgs.ActionMsgs.Srv.CancelGoalResponse, return_code_atom, [])
  #  %{cancel_goal_response_struct | return_code: return_code, goals_canceling: goals_canceling}
  #end
end
