defmodule Rclex.NodeSupervisor do
  @moduledoc false

  use Supervisor, restart: :transient

  alias Rclex.Node
  alias Rclex.EntitiesSupervisor
  alias Rclex.ParameterServer

  def start_link(args) do
    name = Keyword.fetch!(args, :name)
    namespace = Keyword.fetch!(args, :namespace)

    Supervisor.start_link(__MODULE__, args, name: name(name, namespace))
  end

  def name(name, namespace \\ "/") do
    {:global, {:supervisor, name, namespace}}
  end

  # callbacks

  def init(args) do
    start_parameter_server = Keyword.get(args, :start_parameter_server, true)

    children =
      if start_parameter_server do
        [
          {Node, args},
          {EntitiesSupervisor, args},
          {ParameterServer, args}
        ]
      else
        [
          {Node, args},
          {EntitiesSupervisor, args}
        ]
      end

    Supervisor.init(children, strategy: :one_for_all)
  end
end
