defmodule Rclex.ActionServer.GoalSupervisor do
  @moduledoc false

  use DynamicSupervisor

  require Logger

  def start_link(args) do
    action_type = Keyword.fetch!(args, :action_type)
    action_name = Keyword.fetch!(args, :action_name)
    name = Keyword.fetch!(args, :name)
    ns = Keyword.fetch!(args, :namespace)

    Logger.debug("Starting GoalSupervisor for #{action_name}")

    DynamicSupervisor.start_link(__MODULE__, args, name: name(action_type, action_name, name, ns))
  end

  def name(action_type, action_name, name, namespace \\ "/") do
    {:global, {:action_server_goal_supervisor, action_type, action_name, name, namespace}}
  end

  def start_goal(goal_info, goal, execute_callback, handle_accepted_callback, action_server, action_type, action_name, name, namespace \\ "/") do
    DynamicSupervisor.start_child(
      name(action_type, action_name, name, namespace),
      {Rclex.ActionServer.GoalHandle,
       [
         action_server: action_server,
         goal_info: goal_info,
         goal: goal,
         execute_callback: execute_callback,
         handle_accepted_callback: handle_accepted_callback
       ]}
    )
  end

  def cancel_goal(goal_info, action_server, action_type, action_name, name, namespace \\ "/") do
    goal_name = Rclex.ActionServer.GoalHandle.name(action_server, goal_info)

    case GenServer.whereis(goal_name) do
      nil ->
        {:error, :not_found}

      {_atom, _node} ->
        raise("should not happen")

      pid ->
        DynamicSupervisor.terminate_child(name(action_type, action_name, name, namespace), pid)
    end
  end

  # callbacks

  def init(_args) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
