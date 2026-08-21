defmodule Rclex.GraphMonitor do
  @moduledoc """
  Optional GenServer that monitors the ROS 2 graph and emits `:telemetry`
  events when nodes, topics, services, or actions join or leave.

  ## Telemetry events

  All measurements are `%{count: 1}`.

  | Event | Metadata keys |
  |---|---|
  | `[:rclex, :graph, :node_joined]`    | `node_name`, `node_namespace` |
  | `[:rclex, :graph, :node_left]`      | `node_name`, `node_namespace` |
  | `[:rclex, :graph, :topic_joined]`   | `topic_name`, `topic_types` |
  | `[:rclex, :graph, :topic_left]`     | `topic_name`, `topic_types` |
  | `[:rclex, :graph, :service_joined]` | `service_name`, `service_types` |
  | `[:rclex, :graph, :service_left]`   | `service_name`, `service_types` |
  | `[:rclex, :graph, :action_joined]`  | `action_name`, `action_types` |
  | `[:rclex, :graph, :action_left]`    | `action_name`, `action_types` |

  ## Enabling

  Pass `graph_monitor: true` when starting a node:

      Rclex.start_node("my_node", graph_monitor: true)

  Requires the `:telemetry` library to be listed as a dependency in your project.

  ## `on_entity/4`

  Registers a callback that fires when a ROS entity is visible in the graph.
  The callback receives the matching `entity_spec` as its only argument. If
  the entity is already present when `on_entity/4` is called, the callback
  fires before the function returns. Otherwise it fires once the first time
  the entity joins. Each firing runs in its own `Task`, so a slow or crashing
  callback cannot block or crash the `GraphMonitor`.

      Rclex.GraphMonitor.on_entity("my_node", {:node, "camera_node", "/sensors"}, fn entity_spec ->
        IO.inspect(entity_spec, label: "joined")
      end)
  """

  use GenServer
  alias Rclex.Node

  @typedoc "Identifies a ROS graph entity to watch."
  @type entity_spec ::
          {:node, node_name :: String.t(), node_namespace :: String.t()}
          | {:topic, topic_name :: String.t()}
          | {:service, service_name :: String.t()}
          | {:action, action_name :: String.t()}

  def start_link(args) do
    name = Keyword.fetch!(args, :name)
    namespace = Keyword.fetch!(args, :namespace)
    GenServer.start_link(__MODULE__, args, name: name(name, namespace))
  end

  def name(name, namespace \\ "/") do
    {:global, {:graph_monitor, name, namespace}}
  end

  @doc """
  Registers `callback` to be called with `entity_spec` when it is present in
  the ROS graph. If the entity is already visible, `callback` is invoked
  before this function returns. Otherwise it fires once the first time the
  entity appears. Each firing runs in its own `Task`.

  `entity_spec` can be:

  - `{:node, node_name, node_namespace}` — a ROS node
  - `{:topic, topic_name}` — a topic (any publisher or subscriber)
  - `{:service, service_name}` — a service server
  - `{:action, action_name}` — an action server

  ### opts

  - `:namespace` — namespace of the *monitor* node. Defaults to `"/"`.
  """
  @spec on_entity(
          monitor_node_name :: String.t(),
          entity_spec :: entity_spec(),
          callback :: (entity_spec() -> any()),
          opts :: [namespace: String.t()]
        ) :: :ok
  def on_entity(node_name, entity_spec, callback, opts \\ []) do
    namespace = Keyword.get(opts, :namespace, "/")
    GenServer.call(name(node_name, namespace), {:on_entity, entity_spec, callback})
  end

  @doc """
  Return the current graph snapshot maintained by the monitor.

  The snapshot is a map with keys `:nodes`, `:topics`, `:services`, and
  `:actions`, each being a `MapSet` of the currently known graph entities.

  ### opts

  - `:namespace` — namespace of the *monitor* node. Defaults to `"/"`.
  """
  @spec get_snapshot(monitor_node_name :: String.t(), opts :: [namespace: String.t()]) :: map()
  def get_snapshot(node_name, opts \\ []) do
    namespace = Keyword.get(opts, :namespace, "/")
    GenServer.call(name(node_name, namespace), :get_snapshot)
  end

  # callbacks

  @doc false
  def init(args) do
    node_name = Keyword.fetch!(args, :name)
    namespace = Keyword.fetch!(args, :namespace)
    snapshot = fetch_snapshot(node_name, namespace)
    {:ok, %{node_name: node_name, namespace: namespace, snapshot: snapshot, pending: []}}
  end

  @doc false
  def handle_call({:on_entity, entity_spec, callback}, _from, state) do
    new_state =
      if entity_present?(entity_spec, state.snapshot) do
        Task.start(fn -> callback.(entity_spec) end)
        state
      else
        %{state | pending: [{entity_spec, callback} | state.pending]}
      end

    {:reply, :ok, new_state}
  end

  @doc false
  def handle_call(:get_snapshot, _from, state) do
    {:reply, state.snapshot, state}
  end

  @doc false
  def handle_cast(:graph_changed, state) do
    new_snapshot = fetch_snapshot(state.node_name, state.namespace)
    diff = compute_diff(state.snapshot, new_snapshot)
    emit_telemetry(diff)
    pending = fire_pending(diff, state.pending)
    {:noreply, %{state | snapshot: new_snapshot, pending: pending}}
  end

  # helpers

  defp fetch_snapshot(node_name, namespace) do
    server = Node.name(node_name, namespace)

    %{
      nodes: GenServer.call(server, {:get_node_names}) |> MapSet.new(),
      topics: GenServer.call(server, {:get_topic_names_and_types, false}) |> MapSet.new(),
      services: GenServer.call(server, {:get_service_names_and_types}) |> MapSet.new(),
      actions: GenServer.call(server, {:action_get_names_and_types}) |> MapSet.new()
    }
  end

  defp compute_diff(old, new) do
    %{
      nodes_joined: MapSet.difference(new.nodes, old.nodes),
      nodes_left: MapSet.difference(old.nodes, new.nodes),
      topics_joined: MapSet.difference(new.topics, old.topics),
      topics_left: MapSet.difference(old.topics, new.topics),
      services_joined: MapSet.difference(new.services, old.services),
      services_left: MapSet.difference(old.services, new.services),
      actions_joined: MapSet.difference(new.actions, old.actions),
      actions_left: MapSet.difference(old.actions, new.actions)
    }
  end

  @doc false
  def telemetry_available? do
    telemetry_module = Application.get_env(:rclex, :telemetry_module, :telemetry)
    Code.ensure_loaded?(telemetry_module) and function_exported?(telemetry_module, :execute, 3)
  end

  defp emit_telemetry(diff) do
    if telemetry_available?() do
      emit_node_telemetry(diff)
      emit_topic_telemetry(diff)
      emit_service_telemetry(diff)
      emit_action_telemetry(diff)
    else
      :ok
    end
  end

  defp emit_node_telemetry(diff) do
    for {n, ns} <- diff.nodes_joined,
        do:
          emit_telemetry([:rclex, :graph, :node_joined], %{count: 1}, %{
            node_name: n,
            node_namespace: ns
          })

    for {n, ns} <- diff.nodes_left,
        do:
          emit_telemetry([:rclex, :graph, :node_left], %{count: 1}, %{
            node_name: n,
            node_namespace: ns
          })
  end

  defp emit_topic_telemetry(diff) do
    for {n, t} <- diff.topics_joined,
        do:
          emit_telemetry([:rclex, :graph, :topic_joined], %{count: 1}, %{
            topic_name: n,
            topic_types: t
          })

    for {n, t} <- diff.topics_left,
        do:
          emit_telemetry([:rclex, :graph, :topic_left], %{count: 1}, %{
            topic_name: n,
            topic_types: t
          })
  end

  defp emit_service_telemetry(diff) do
    for {n, t} <- diff.services_joined,
        do:
          emit_telemetry([:rclex, :graph, :service_joined], %{count: 1}, %{
            service_name: n,
            service_types: t
          })

    for {n, t} <- diff.services_left,
        do:
          emit_telemetry([:rclex, :graph, :service_left], %{count: 1}, %{
            service_name: n,
            service_types: t
          })
  end

  defp emit_action_telemetry(diff) do
    for {n, t} <- diff.actions_joined,
        do:
          emit_telemetry([:rclex, :graph, :action_joined], %{count: 1}, %{
            action_name: n,
            action_types: t
          })

    for {n, t} <- diff.actions_left,
        do:
          emit_telemetry([:rclex, :graph, :action_left], %{count: 1}, %{
            action_name: n,
            action_types: t
          })
  end

  defp entity_present?({:node, node_name, node_namespace}, snapshot),
    do: MapSet.member?(snapshot.nodes, {node_name, node_namespace})

  defp entity_present?({:topic, topic_name}, snapshot),
    do: Enum.any?(snapshot.topics, fn {name, _} -> name == topic_name end)

  defp entity_present?({:service, service_name}, snapshot),
    do: Enum.any?(snapshot.services, fn {name, _} -> name == service_name end)

  defp entity_present?({:action, action_name}, snapshot),
    do: Enum.any?(snapshot.actions, fn {name, _} -> name == action_name end)

  defp fire_pending(diff, pending) do
    Enum.reject(pending, fn {entity_spec, callback} ->
      matched = entity_in_joined?(entity_spec, diff)
      if matched, do: Task.start(fn -> callback.(entity_spec) end)
      matched
    end)
  end

  defp entity_in_joined?({:node, name, namespace}, diff),
    do: MapSet.member?(diff.nodes_joined, {name, namespace})

  defp entity_in_joined?({:topic, name}, diff),
    do: Enum.any?(diff.topics_joined, fn {n, _} -> n == name end)

  defp entity_in_joined?({:service, name}, diff),
    do: Enum.any?(diff.services_joined, fn {n, _} -> n == name end)

  defp entity_in_joined?({:action, name}, diff),
    do: Enum.any?(diff.actions_joined, fn {n, _} -> n == name end)

  # Conditionally emit telemetry if the :telemetry module is available
  defp emit_telemetry(event, measurements, metadata) do
    if Code.ensure_loaded?(:telemetry) do
      apply(:telemetry, :execute, [event, measurements, metadata])
    end
  end
end
