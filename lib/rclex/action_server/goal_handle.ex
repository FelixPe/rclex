defmodule Rclex.ActionServer.GoalHandle do
  @moduledoc false

  use GenServer, restart: :temporary

  require Logger

  alias Rclex.Pkgs.ActionMsgs.Msg.GoalStatus
  alias Rclex.Nif
  alias Rclex.ActionServer

  def start_link(args) do
    goal_info = Keyword.fetch!(args, :goal_info)
    action_type = Keyword.fetch!(args, :action_type)
    action_name = Keyword.fetch!(args, :action_name)
    name = Keyword.fetch!(args, :name)
    namespace = Keyword.fetch!(args, :namespace)

    Logger.debug(
      "#{__MODULE__} [uuid: #{Base.encode16(goal_info.goal_id.uuid)}]: start_link (stamp: #{inspect(goal_info.stamp)})"
    )

    GenServer.start_link(__MODULE__, args,
      name: name(goal_info, action_type, action_name, name, namespace)
    )
  end

  def name(goal_info, action_type, action_name, name, namespace) do
    uuid = get_uuid(goal_info)
    {:global, {:action_server_goal_handle, uuid, action_type, action_name, name, namespace}}
  end

  defp get_uuid(goal_info) when is_struct(goal_info, Rclex.Pkgs.ActionMsgs.Msg.GoalInfo) do
    goal_info.goal_id.uuid
  end

  def get_status(goal_info, action_type, action_name, name, namespace) do
    case GenServer.whereis(name(goal_info, action_type, action_name, name, namespace)) do
      nil -> {:error, :not_found}
      {_atom, _node} -> raise("should not happen")
      pid -> GenServer.call(pid, {:get_status})
    end
  end

  def execute_goal(goal_info, action_type, action_name, name, namespace) do
    case GenServer.whereis(name(goal_info, action_type, action_name, name, namespace)) do
      nil -> {:error, :not_found}
      {_atom, _node} -> raise("should not happen")
      pid -> GenServer.call(pid, {:execute_goal})
    end
  end

  def cancel_goal(goal_info, action_type, action_name, name, namespace) do
    case GenServer.whereis(name(goal_info, action_type, action_name, name, namespace)) do
      nil -> {:error, :not_found}
      {_atom, _node} -> raise("should not happen")
      pid -> GenServer.call(pid, {:cancel_goal})
    end
  end

  # callbacks
  def init(args) do
    Process.flag(:trap_exit, true)

    action_type = Keyword.fetch!(args, :action_type)
    action_name = Keyword.fetch!(args, :action_name)
    name = Keyword.fetch!(args, :name)
    namespace = Keyword.fetch!(args, :namespace)

    goal_info_struct = Keyword.fetch!(args, :goal_info)
    goal = Keyword.fetch!(args, :goal)
    execute_callback = Keyword.fetch!(args, :execute_callback)

    Logger.debug(
      "#{__MODULE__}: [uuid: #{Base.encode16(goal_info_struct.goal_id.uuid)}] init for #{inspect(name(goal_info_struct, action_type, action_name, name, namespace))}"
    )

    {:ok,
     %{
       action_type: action_type,
       action_name: action_name,
       name: name,
       namespace: namespace,
       goal_info: goal_info_struct,
       goal: goal,
       goal_handle: nil,
       execute_callback: execute_callback,
       task: nil
     }, {:continue, :init}}
  end

  def handle_continue(
        :init,
        %{
          goal_info: goal_info_struct,
          action_type: action_type,
          action_name: action_name,
          name: name,
          namespace: namespace
        } = state
      ) do
    {:ok, goal_handle} =
      ActionServer.accept_new_goal(goal_info_struct, action_type, action_name, name, namespace)

    update_status(apply(GoalStatus, :status_accepted, []), state)
    {:noreply, %{state | goal_handle: goal_handle}}
  end

  def terminate(reason, %{goal_handle: _goal_handle} = state) do
    # deallocation is done by expiring goals in action server
    # Nif.rcl_action_goal_handle_fini!(goal_handle)

    Logger.debug(
      "#{__MODULE__}: finished goal_handle because #{inspect(reason)} #{inspect(state)}"
    )
  end

  def terminate(reason, state) do
    Logger.debug("#{__MODULE__}: #{inspect(reason)} #{inspect(state)}")
  end

  def handle_call(
        {:get_status},
        _from,
        %{
          goal_handle: goal_handle
        } = state
      ) do
    status = Nif.rcl_action_goal_handle_get_status!(goal_handle)
    {:reply, status_to_atom(status), state}
  end

  # In this case the task is already running, so we just return :ok.
  def handle_call(:execute_goal, _from, %{task: task} = state)
      when is_struct(task, Task) do
    Logger.error("#{__MODULE__}: Goal was already executed.")
    {:reply, :ok, state}
  end

  def handle_call(
        {:execute_goal},
        _from,
        %{
          goal: goal,
          goal_info: goal_info,
          action_type: action_type,
          action_name: action_name,
          name: name,
          namespace: namespace,
          execute_callback: execute_callback
        } = state
      ) do
    update_goal_state(:goal_event_execute, state)

    publish_feedback = fn feedback ->
      ActionServer.publish_feedback(
        goal_info.goal_id,
        feedback,
        action_type,
        action_name,
        name,
        namespace
      )
    end

    task =
      Task.Supervisor.async_nolink(
        {:via, PartitionSupervisor, {Rclex.TaskSupervisors, self()}},
        fn ->
          # return a result using handle_info({_task_ref, result}, ...)
          execute_callback.(goal, publish_feedback)
        end
      )

    {:reply, :ok, %{state | task: task}}
  end

  def handle_call(
        {:cancel_goal},
        _from,
        %{
          task: task,
          goal_info: goal_info
        } = state
      ) do
    update_goal_state(:goal_event_cancel_goal, state)

    Logger.debug("#{__MODULE__}: Cancel goal [#{Base.encode16(get_uuid(goal_info))}].")

    ret = Task.shutdown(task, 100)
    update_goal_state(:goal_event_canceled, state)
    set_result(nil, state)

    {:stop, :normal, ret, state}
  end

  # The goal execution completed successfully
  def handle_info(
        {_task_ref, result},
        %{
          task: task,
          goal_info: goal_info
        } = state
      ) do
    # We don't care about the DOWN message now, so let's demonitor and flush it
    Process.demonitor(task.ref, [:flush])

    # Hand over the result to the action server

    update_goal_state(:goal_event_succeed, state)
    set_result(result, state)

    Logger.debug(
      "#{__MODULE__}: Goal [#{Base.encode16(get_uuid(goal_info))}] execution completed with #{inspect(result)}."
    )

    {:stop, :normal, state}
  end

  # The goal execution failed
  def handle_info(
        {:DOWN, _ref, :process, _pid, reason},
        %{task: _task, goal_info: goal_info} = state
      ) do
    update_goal_state(:goal_event_abort, state)
    set_result(nil, state)

    Logger.error(
      "#{__MODULE__}: Goal [#{Base.encode16(get_uuid(goal_info))}] execution failed because of #{inspect(reason)}."
    )

    {:stop, :normal, state}
  end

  # helpers

  @state_to_atom %{
    0 => :status_unknown,
    1 => :status_accepted,
    2 => :status_executing,
    3 => :status_canceling,
    4 => :status_succeeded,
    5 => :status_canceled,
    6 => :status_aborted
  }

  defp status_to_atom(value) do
    Map.fetch!(@state_to_atom, value)
  end

  def active?(goal_handle) do
    Nif.rcl_action_goal_handle_is_active!(goal_handle)
  end

  def cancalable?(goal_handle) do
    Nif.rcl_action_goal_handle_is_cancelable!(goal_handle)
  end

  def valid?(goal_handle) do
    Nif.rcl_action_goal_handle_is_valid!(goal_handle)
  end

  @spec update_goal_state(
          :goal_event_execute
          | :goal_event_cancel_goal
          | :goal_event_succeed
          | :goal_event_abort
          | :goal_event_canceled,
          map()
        ) :: any()
  defp update_goal_state(event, %{goal_handle: goal_handle} = state)
       when is_atom(event) and
              event in [
                :goal_event_execute,
                :goal_event_cancel_goal,
                :goal_event_succeed,
                :goal_event_abort,
                :goal_event_canceled
              ] do
    :ok = Nif.rcl_action_update_goal_state!(goal_handle, event)
    status = Nif.rcl_action_goal_handle_get_status!(goal_handle)
    update_status(status, state)
  end

  defp update_status(
         status,
         %{
           goal_info: goal_info,
           action_type: action_type,
           action_name: action_name,
           name: name,
           namespace: namespace
         } = _state
       ) do
    goal_status = gen_goal_status(goal_info, status)
    ActionServer.update_status(goal_status, action_type, action_name, name, namespace)
  end

  def gen_goal_status(goal_info, status) do
    goal_status = struct(GoalStatus)
    %{goal_status | goal_info: goal_info, status: status}
  end

  defp set_result(
         result,
         %{
           goal_handle: goal_handle,
           goal_info: goal_info,
           action_type: action_type,
           action_name: action_name,
           name: name,
           namespace: namespace
         } =
           _state
       ) do
    status = Nif.rcl_action_goal_handle_get_status!(goal_handle)

    :ok =
      ActionServer.set_result(
        status,
        result,
        goal_info.goal_id,
        action_type,
        action_name,
        name,
        namespace
      )
  end
end
