defmodule Rclex.NodesSupervisor do
  @moduledoc false

  use DynamicSupervisor

  def start_link(args) do
    DynamicSupervisor.start_link(__MODULE__, args, name: name())
  end

  def name() do
    __MODULE__
  end

  def get_nodes(opts \\ []) when is_list(opts) do
    node_pids =
      name()
      |> DynamicSupervisor.which_children()
      |> Enum.flat_map(fn {_, pid, _, _} -> if is_pid(pid), do: [pid], else: [] end)

    :global.registered_names()
    |> Enum.flat_map(&node_from_registration(&1, node_pids))
    |> Enum.filter(&matches_filters?(&1, opts))
  end

  def start_child(
        context,
        name,
        namespace \\ "/",
        graph_change_callback \\ nil,
        ros_args \\ [],
        graph_monitor \\ false
      ) do
    DynamicSupervisor.start_child(
      name(),
      {Rclex.NodeSupervisor,
       [
         context: context,
         name: name,
         namespace: namespace,
         graph_change_callback: graph_change_callback,
         ros_args: ros_args,
         graph_monitor: graph_monitor
       ]}
    )
  end

  def terminate_child(name, namespace \\ "/") do
    name = Rclex.NodeSupervisor.name(name, namespace)

    case GenServer.whereis(name) do
      nil -> {:error, :not_found}
      pid -> DynamicSupervisor.terminate_child(name(), pid)
    end
  end

  defp node_from_registration({:supervisor, node_name, namespace} = registration, node_pids)
       when is_binary(node_name) and is_binary(namespace) do
    if :global.whereis_name(registration) in node_pids do
      [%{name: node_name, namespace: namespace}]
    else
      []
    end
  end

  defp node_from_registration(_registration, _node_pids), do: []

  defp matches_filters?(node, opts) do
    Enum.all?(opts, fn {key, value} -> Map.get(node, key) == value end)
  end

  # callbacks

  def init(_args) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
