defmodule Rclex.ActionServerSupervisor do
  @moduledoc false

  use Supervisor, restart: :transient

  alias Rclex.ActionServer
  alias Rclex.ActionServer.GoalSupervisor

  def start_link(args) do
    action_type = Keyword.fetch!(args, :action_type)
    action_name = Keyword.fetch!(args, :action_name)
    name = Keyword.fetch!(args, :name)
    ns = Keyword.fetch!(args, :namespace)

    Supervisor.start_link(__MODULE__, args, name: name(action_type, action_name, name, ns))
  end

  def name(action_type, action_name, name, namespace \\ "/") do
    {:global, {:action_server_supervisor, action_type, action_name, name, namespace}}
  end

  # callbacks

  def init(args) do
    children = [
      {ActionServer, args},
      {GoalSupervisor, args}
    ]

    Supervisor.init(children, strategy: :one_for_all)
  end
end
