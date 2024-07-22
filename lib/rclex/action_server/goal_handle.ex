defmodule Rclex.ActionServer.GoalHandle do
  @moduledoc false

  use GenServer, restart: :temporary

  require Logger

  alias Rclex.Nif

  def start_link(args) do
    goal_info = Keyword.fetch!(args, :goal_info)
    GenServer.start_link(__MODULE__, args, name: name(goal_info))
  end

  def name(goal_info) do
    goal_id = Nif.rcl_action_goal_info_get_uuid!(goal_info)
    {:global, {:action_server_goal_handle, goal_id}}
  end

  def init(args) do
    Process.flag(:trap_exit, true)

    action_server = Keyword.fetch!(args, :action_server)
    action_server_pid = Keyword.fetch!(args, :action_server)
    goal_info = Keyword.fetch!(args, :goal_info)
    goal_request = Keyword.fetch!(args, :goal_request)
    cancel_request = false

    {:ok,
     %{
       action_server: action_server,
       goal_info: goal_info,
       goal_request: goal_request,
       cancel_request: cancel_request
     }}
  end

  def terminate(reason, state) do
    # Nif.rcl_node_fini!(state.node)

    Logger.debug("#{__MODULE__}: #{inspect(reason)} #{inspect(state)}")
  end

  def get_status(goal_handle) do
    status = Nif.rcl_action_goal_handle_get_status!(goal_handle)
    status_to_atom(status)
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

  @state_to_atom %{
    0 => :unknown,
    1 => :accepted,
    2 => :executing,
    3 => :canceling,
    4 => :succeeded,
    5 => :canceled,
    6 => :aborted
  }

  @atom_to_state %{
    :unknown => 0,
    :accepted => 1,
    :executing => 2,
    :canceling => 3,
    :succeeded => 4,
    :canceled => 5,
    :aborted => 6
  }

  defp atom_to_status(value) do
    Map.fetch!(@atom_to_state, value)
  end

  defp status_to_atom(value) do
    Map.fetch!(@state_to_atom, value)
  end
end
