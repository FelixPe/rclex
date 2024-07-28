defmodule Rclex.ActionServer.GoalHandle do
  @moduledoc false

  use GenServer, restart: :temporary

  require Logger

  alias Rclex.Nif

  def start_link(args) do
    action_server = Keyword.fetch!(args, :action_server)
    goal_info = Keyword.fetch!(args, :goal_info)
    GenServer.start_link(__MODULE__, args, name: name(action_server, goal_info))
  end

  def name(action_server, goal_info) do
    {:ok, uuid} = Nif.rcl_action_goal_info_get_uuid!(goal_info)
    {:global, {:action_server_goal_handle, action_server, uuid}}
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
    goal_info = Keyword.fetch!(args, :goal_info)
    goal = Keyword.fetch!(args, :goal)
    cancel_requested = false
    goal_handle = Nif.rcl_action_accept_new_goal!(action_server, goal_info)

    Logger.debug("#{__MODULE__}: init for #{inspect(name(action_server, goal_info))}")

    {:ok,
     %{
       action_server: action_server,
       goal_info: goal_info,
       goal: goal,
       cancel_requested: cancel_requested,
       goal_handle: goal_handle
     }}
  end

  def terminate(reason, %{goal_handle: goal_handle} = state) do
    Nif.rcl_action_goal_handle_fini!(goal_handle)

    Logger.debug("#{__MODULE__}: #{inspect(reason)} #{inspect(state)}")
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

  def active?(goal_handle) do
    Nif.rcl_action_goal_handle_is_active!(goal_handle)
  end

  def cancalable?(goal_handle) do
    Nif.rcl_action_goal_handle_is_cancelable!(goal_handle)
  end

  def valid?(goal_handle) do
    Nif.rcl_action_goal_handle_is_valid!(goal_handle)
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

  def handle_call(
        {:cancel_goal},
        _from,
        %{
          goal_handle: goal_handle
        } = state
      ) do
    ret = Nif.rcl_action_update_goal_state!(goal_handle, :goal_event_cancel_goal)

    # TODO: terminate execute task

    {:reply, ret, %{state | cancel_requested: true}}
  end

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
end
