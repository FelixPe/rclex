defmodule Rclex.NodeSupervisor do
  @moduledoc false

  use Supervisor, restart: :transient

  alias Rclex.Node
  alias Rclex.EntitiesSupervisor
  alias Rclex.GraphMonitor
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
    graph_monitor = Keyword.get(args, :graph_monitor, false)
    node_name = Keyword.fetch!(args, :name)
    namespace = Keyword.fetch!(args, :namespace)

    args =
      if graph_monitor do
        monitor_name = GraphMonitor.name(node_name, namespace)
        notify = fn -> GenServer.cast(monitor_name, :graph_changed) end

        combined =
          case Keyword.get(args, :graph_change_callback) do
            nil -> notify
            user_cb -> fn -> user_cb.(); notify.() end
          end

        Keyword.put(args, :graph_change_callback, combined)
      else
        args
      end

    children = [{Node, args}, {EntitiesSupervisor, args}]
    children = if start_parameter_server, do: children ++ [{ParameterServer, args}], else: children
    children = if graph_monitor, do: children ++ [{GraphMonitor, args}], else: children

    Supervisor.init(children, strategy: :one_for_all)
  end
end
