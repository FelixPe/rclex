defmodule Rclex.ActionServer.GoalHandle do
  @moduledoc false

  use GenServer, restart: :temporary

  require Logger

  alias Rclex.Nif
  alias Rclex.ActionServer

  def start_link(args) do
    action_server = Keyword.fetch!(args, :action_server)
    goal_info = Keyword.fetch!(args, :goal_info)
    Logger.debug("goal_info: #{inspect(goal_info)}")
    GenServer.start_link(__MODULE__, args, name: name(action_server, goal_info))
  end

  def name(action_server, goal_info) do
    uuid = get_uuid(goal_info)
    {:global, {:action_server_goal_handle, action_server, uuid}}
  end

  defp get_uuid(goal_info) when is_struct(goal_info, Rclex.Pkgs.ActionMsgs.Msg.GoalInfo) do
    goal_info.goal_id.uuid
  end

  def get_status(action_server, goal_info) do
    case GenServer.whereis(name(action_server, goal_info)) do
      nil -> {:error, :not_found}
      {_atom, _node} -> raise("should not happen")
      pid -> GenServer.call(pid, {:get_status})
    end
  end

  @doc """
  Transition the goal state machine, excepting one of the following event:
   - :goal_event_execute
   - :goal_event_cancel_goal
   - :goal_event_succeed
   - :goal_event_abort
   - :goal_event_canceled
  """
  def update_state(action_server, goal_info, event \\ :goal_event_execute) when is_atom(event) do
    case GenServer.whereis(name(action_server, goal_info)) do
      nil -> {:error, :not_found}
      {_atom, _node} -> raise("should not happen")
      pid -> GenServer.call(pid, {:update_state, event})
    end
  end

  @doc """
  Transition the goal state machine, excepting one of the following event:
   - :goal_event_execute
   - :goal_event_cancel_goal
   - :goal_event_succeed
   - :goal_event_abort
   - :goal_event_canceled
  """
  def execute_goal(action_server, goal_info) do
    case GenServer.whereis(name(action_server, goal_info)) do
      nil -> {:error, :not_found}
      {_atom, _node} -> raise("should not happen")
      pid -> GenServer.call(pid, {:execute_goal})
    end
  end

  @doc """
  Transition the goal state machine, excepting one of the following event:
   - :goal_event_execute
   - :goal_event_cancel_goal
   - :goal_event_succeed
   - :goal_event_abort
   - :goal_event_canceled
  """
  def cancel_goal(action_server, goal_info) do
    case GenServer.whereis(name(action_server, goal_info)) do
      nil -> {:error, :not_found}
      {_atom, _node} -> raise("should not happen")
      pid -> GenServer.call(pid, {:cancel_goal})
    end
  end

  # callbacks
  def init(args) do
    Process.flag(:trap_exit, true)

    action_server = Keyword.fetch!(args, :action_server)
    action_type = Keyword.fetch!(args, :action_type)
    action_name = Keyword.fetch!(args, :action_name)
    name = Keyword.fetch!(args, :name)
    namespace = Keyword.fetch!(args, :namespace)

    goal_info_struct = Keyword.fetch!(args, :goal_info)
    goal = Keyword.fetch!(args, :goal)
    execute_callback = Keyword.fetch!(args, :execute_callback)
    cancel_requested = false
    goal_handle = accept_new_goal(action_server, goal_info_struct)

    Logger.debug("#{__MODULE__}: init for #{inspect(name(action_server, goal_info_struct))}")

    {:ok,
     %{
       action_server: action_server,
       action_type: action_type,
       action_name: action_name,
       name: name,
       namespace: namespace,
       goal_info: goal_info_struct,
       goal: goal,
       cancel_requested: cancel_requested,
       goal_handle: goal_handle,
       execute_callback: execute_callback,
       task: nil,
       result: nil
     }}
  end

  def terminate(reason, %{goal_handle: goal_handle} = state) do
    Nif.rcl_action_goal_handle_fini!(goal_handle)

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

  @doc """
  Transition the goal state machine, excepting one of the following event:
   - :goal_event_execute
   - :goal_event_cancel_goal
   - :goal_event_succeed
   - :goal_event_abort
   - :goal_event_canceled
  """
  def handle_call(
        {:update_state, event},
        _from,
        %{
          goal_handle: goal_handle
        } = state
      ) do
    ret = Nif.rcl_action_update_goal_state!(goal_handle, event)
    {:reply, ret, state}
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
          goal_handle: goal_handle,
          goal: goal,
          execute_callback: execute_callback
        } = state
      ) do
    :ok = Nif.rcl_action_update_goal_state!(goal_handle, :goal_event_execute)

    task =
      Task.Supervisor.async_nolink(
        {:via, PartitionSupervisor, {Rclex.TaskSupervisors, self()}},
        fn ->
          # return a result
          execute_callback.(goal)
        end
      )

    # We return :ok and the server will continue running

    {:reply, :ok, %{state | task: task}}
  end

  def handle_call(
        {:cancel_goal},
        _from,
        %{
          goal_handle: goal_handle,
          task: task,
          goal_info: goal_info
        } = state
      ) do
    ret = Nif.rcl_action_update_goal_state!(goal_handle, :goal_event_cancel_goal)

    Logger.debug("#{__MODULE__}: Cancel goal [#{Base.encode16(get_uuid(goal_info))}].")

    Task.shutdown(task, 100)

    {:reply, ret, %{state | cancel_requested: true}}
  end

  # The goal execution completed successfully
  def handle_info({_task_ref, result}, %{task: task, goal_info: goal_info, action_type: action_type, action_name: action_name, name: name, namespace: namespace} = state) do
    # We don't care about the DOWN message now, so let's demonitor and flush it
    Process.demonitor(task.ref, [:flush])

    # Hand over the result to the action server
    ActionServer.set_result(result, goal_info.goal_id, action_type, action_name, name, namespace)


    Logger.debug(
      "#{__MODULE__}: Goal [#{Base.encode16(get_uuid(goal_info))}] execution completed with #{inspect(result)}."
    )

    {:noreply, %{state | task: nil, result: result}}
  end

  # The goal execution failed
  def handle_info(
        {:DOWN, _ref, :process, _pid, reason},
        %{task: _task, goal_info: goal_info} = state
      ) do
    # Log and possibly restart the task...
    Logger.error(
      "#{__MODULE__}: Goal [#{Base.encode16(get_uuid(goal_info))}] execution failed because of #{inspect(reason)}."
    )

    {:noreply, %{state | task: nil}}
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

  defp accept_new_goal(action_server, goal_info_struct) do
    goal_info_msg = apply(Rclex.Pkgs.ActionMsgs.Msg.GoalInfo, :create!, [])
    :ok = apply(Rclex.Pkgs.ActionMsgs.Msg.GoalInfo, :set!, [goal_info_msg, goal_info_struct])
    {:ok, goal_handle} = Nif.rcl_action_accept_new_goal!(action_server, goal_info_msg)
    :ok = apply(Rclex.Pkgs.ActionMsgs.Msg.GoalInfo, :destroy!, [goal_info_msg])
    goal_handle
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
end
