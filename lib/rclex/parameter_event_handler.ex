defmodule Rclex.ParameterEventHandler do
  @moduledoc """
  Helper for subscribing to ROS 2 `/parameter_events` and dispatching
  per-node or per-parameter callbacks.

  The handler is a thin wrapper around `Rclex.start_subscription/5` that
  filters incoming `ParameterEvent` messages by the fully qualified node
  name (e.g. `"/ns/node"`) and optionally by parameter name(s).
  """

  alias Rclex.QoS

  # NOTE: RCL interfaces message types are generated at build time by `mix rclex.gen`.
  # To avoid creating a hard compile-time dependency on the generated ParameterEvent module,
  # we use Module.concat to defer module resolution to runtime (matching the pattern
  # used in Rclex.LifecycleNode).
  @msg_parameter_event Module.concat([Rclex, Pkgs, RclInterfaces, Msg, ParameterEvent])

  @parameter_events_topic "/parameter_events"

  @doc """
  Start a subscription on the local `client_node_name` for ROS 2 parameter
  events.

  `callback` is invoked with a `%Rclex.Pkgs.RclInterfaces.Msg.ParameterEvent{}`
  struct whenever an event passes the configured filters.

  ## Options

  - `:namespace` — namespace of the client node. Defaults to `"/"`.
  - `:node_filter` — a fully qualified node name (e.g. `"/ns/node"`) to
    filter events by. Defaults to `nil` (no filter).
  - `:parameter_filter` — a list of parameter names to filter by. Only
    events touching at least one of these parameters are forwarded.
    Defaults to `nil` (no filter).
  - `:qos` — defaults to `Rclex.QoS.profile_parameter_events/0`.
  """
  @spec start(
          callback :: (Rclex.parameter_event() -> any()),
          client_node_name :: String.t(),
          opts :: keyword()
        ) :: :ok | {:error, term()}
  def start(callback, client_node_name, opts \\ [])
      when is_function(callback, 1) and is_binary(client_node_name) and is_list(opts) do
    namespace = Keyword.get(opts, :namespace, "/")
    node_filter = Keyword.get(opts, :node_filter)
    parameter_filter = Keyword.get(opts, :parameter_filter)
    qos = Keyword.get(opts, :qos, QoS.profile_parameter_events())

    wrapped =
      fn event ->
        if matches?(event, node_filter, parameter_filter), do: callback.(event), else: :ok
      end

    Rclex.start_subscription(
      wrapped,
      @msg_parameter_event,
      @parameter_events_topic,
      client_node_name,
      namespace: namespace,
      qos: qos
    )
  end

  @doc """
  Stop the parameter-event subscription on `client_node_name`.
  """
  @spec stop(client_node_name :: String.t(), opts :: keyword()) :: :ok | {:error, :not_found}
  def stop(client_node_name, opts \\ [])
      when is_binary(client_node_name) and is_list(opts) do
    namespace = Keyword.get(opts, :namespace, "/")

    Rclex.stop_subscription(@msg_parameter_event, @parameter_events_topic, client_node_name,
      namespace: namespace
    )
  end

  defp matches?(event, node_filter, parameter_filter) do
    matches_node?(event, node_filter) and matches_parameter?(event, parameter_filter)
  end

  defp matches_node?(_event, nil), do: true
  defp matches_node?(event, node_filter), do: Map.fetch!(event, :node) == node_filter

  defp matches_parameter?(_event, nil), do: true
  defp matches_parameter?(_event, []), do: true

  defp matches_parameter?(event, names) when is_list(names) do
    new_parameters = Map.fetch!(event, :new_parameters) || []
    changed_parameters = Map.fetch!(event, :changed_parameters) || []
    deleted_parameters = Map.fetch!(event, :deleted_parameters) || []

    event_names =
      (new_parameters ++ changed_parameters ++ deleted_parameters)
      |> Enum.map(&Map.fetch!(&1, :name))

    Enum.any?(event_names, &(&1 in names))
  end
end
