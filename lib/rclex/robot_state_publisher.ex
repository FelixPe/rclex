defmodule Rclex.RobotStatePublisher do
  @moduledoc """
  Supervised URDF joint-state to TF publisher.

  `start_link/1` requires a parsed `:model` and a string `:node_name`. Options:
  `:namespace` (default `"/"`), `:node_mode` (`:own`, default, or `:borrow`),
  `:joint_states_topic` (default `"/joint_states"`), `:frame_prefix` (default `""`),
  `:joint_states_qos`, `:tf_qos`, `:tf_static_qos`, and shared fallback `:qos`.
  `:name` optionally registers the GenServer. TF topics remain absolute.

  Own mode creates and cleans up its ROS node. Borrow mode requires an existing
  node and TF broadcaster; it owns only its new JointState subscription. Existing
  JointState subscriptions are never adopted. All fixed edges are published in
  one initial durable TFMessage. Generated message modules are resolved at runtime.

  Subscription acquisition has a five-second startup deadline. A guardian waits
  for the exact node PID's queued acquisition beyond that deadline and stops only
  the returned subscription PID if startup fails or the worker exits. A suspended
  node can delay this cleanup until it resumes or dies; existing subscriptions
  are never stopped. Owned shutdown terminates only the created node supervisor
  PID, without name-based TF2 teardown or removal of replacement resources.

  `publish_joint_state/2` accepts a JointState-compatible map or generated struct
  and returns `:ok` or `{:error, reason}`. Invalid messages are rejected atomically.
  Unknown joint names are validated but ignored. Absent positions are never cached
  or restamped; mimics use only source positions from the current update.
  Backwards timestamps return `{:error, {:backwards_stamp, joint_name}}`; equal
  timestamps are allowed. Restart this worker to reset the timestamp epoch after
  a simulation-time reset (clear listener dynamic history separately).
  """

  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, Keyword.take(opts, [:name]))
  end

  @doc "Synchronously validates and publishes one JointState update."
  def publish_joint_state(server, message), do: GenServer.call(server, {:joint_state, message})

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)

    with :ok <- validate_options(opts),
         {:ok, initial} <- Rclex.Urdf.transforms(opts[:model], %{}, %{sec: 0, nanosec: 0}, opts),
         {:ok, types} <- message_types() do
      state = %{
        model: opts[:model],
        node_name: opts[:node_name],
        namespace: Keyword.get(opts, :namespace, "/"),
        node_mode: Keyword.get(opts, :node_mode, :own),
        topic: resolve_topic(opts),
        opts: opts,
        types: types,
        node_supervisor_pid: nil,
        node_pid: nil,
        subscription_pid: nil,
        monitor: nil,
        stamps: %{}
      }

      case acquire_node(state) do
        {:ok, state} -> initialize_transport(state, initial.static)
        {:error, reason} -> {:stop, reason}
      end
    else
      {:error, reason} -> {:stop, reason}
    end
  end

  defp initialize_transport(state, static) do
    with :ok <- safely(fn -> broadcaster(state) end),
         {:ok, subscribed} <- subscribe(state) do
      initialize_static(subscribed, static)
    else
      {:error, reason} ->
        cleanup(state)
        {:stop, reason}
    end
  end

  defp initialize_static(state, static) do
    case safely(fn -> broadcast(static, :static, state) end) do
      :ok ->
        {:ok, state}

      {:error, reason} ->
        cleanup(state)
        {:stop, reason}
    end
  end

  defp acquire_node(%{node_mode: :own} = state) do
    case safely(fn ->
           Rclex.NodesSupervisor.start_child(
             Rclex.Context.get(),
             state.node_name,
             state.namespace,
             nil,
             Rclex.RosArgs.node_ros_args([])
           )
         end) do
      {:ok, pid} ->
        owned = %{state | node_supervisor_pid: pid}

        case monitor_owned_node(owned) do
          {:ok, state} ->
            {:ok, state}

          error ->
            cleanup(owned)
            error
        end

      {:error, {:already_started, _pid}} ->
        {:error, :already_started}

      error ->
        error
    end
  end

  defp acquire_node(state), do: monitor_node(state)

  defp monitor_owned_node(state) do
    safely(fn ->
      state.node_supervisor_pid
      |> Supervisor.which_children()
      |> List.keyfind(Rclex.Node, 0)
      |> monitor_owned_child(state)
    end)
  end

  defp monitor_owned_child({Rclex.Node, pid, _, _}, state) when is_pid(pid),
    do: {:ok, %{state | node_pid: pid, monitor: Process.monitor(pid)}}

  defp monitor_owned_child(_child, _state), do: {:error, :node_not_found}

  defp monitor_node(state) do
    case GenServer.whereis(Rclex.Node.name(state.node_name, state.namespace)) do
      nil -> {:error, :node_not_found}
      pid -> {:ok, %{state | node_pid: pid, monitor: Process.monitor(pid)}}
    end
  end

  defp broadcaster(%{node_mode: :own} = state) do
    with :ok <- ensure_tf_publisher(state, "/tf", :tf_qos, %Rclex.QoS{depth: 100}),
         :ok <-
           ensure_tf_publisher(state, "/tf_static", :tf_static_qos, %Rclex.QoS{
             depth: 1,
             durability: :transient_local
           }) do
      Rclex.Tf2.start_broadcaster(state.node_name, state.opts)
    end
  end

  defp broadcaster(state) do
    if Enum.all?(["/tf", "/tf_static"], fn topic ->
         GenServer.whereis(
           Rclex.Publisher.name(state.types.tf_message, topic, state.node_name, state.namespace)
         )
       end) do
      :ok
    else
      {:error, :broadcaster_not_found}
    end
  end

  defp ensure_tf_publisher(state, topic, qos_key, default) do
    qos = Keyword.get(state.opts, qos_key, Keyword.get(state.opts, :qos, default))

    case GenServer.call(
           state.node_pid,
           {:start_publisher, state.types.tf_message, topic, [qos: qos]},
           :infinity
         ) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
      error -> error
    end
  end

  defp subscribe(state) do
    server = self()

    qos =
      Keyword.get(
        state.opts,
        :joint_states_qos,
        Keyword.get(state.opts, :qos, Rclex.QoS.profile_sensor_data())
      )

    callback = fn message -> GenServer.cast(server, {:joint_state, message}) end

    request =
      {:start_subscription, callback, state.types.joint_state, state.topic,
       [qos: qos, inline_callback: true]}

    {guardian, monitor} =
      spawn_monitor(fn -> acquire_subscription(server, state.node_pid, request) end)

    receive do
      {^guardian, {:ok, pid}} ->
        Process.demonitor(monitor, [:flush])
        {:ok, %{state | subscription_pid: pid}}

      {^guardian, error} ->
        Process.demonitor(monitor, [:flush])
        error

      {:DOWN, ^monitor, :process, ^guardian, reason} ->
        {:error, {:subscription_guardian_down, reason}}
    after
      5_000 ->
        Process.demonitor(monitor, [:flush])
        {:error, :subscription_start_timeout}
    end
  end

  defp acquire_subscription(server, node, request) do
    monitor = Process.monitor(server)
    result = safely(fn -> GenServer.call(node, request, :infinity) end)
    send(server, {self(), subscription_result(result)})
    guard_subscription(result, server, monitor)
  end

  defp subscription_result({:error, {:already_started, _pid}}), do: {:error, :already_started}
  defp subscription_result(result), do: result

  defp guard_subscription({:ok, pid}, server, monitor) do
    receive do
      {:DOWN, ^monitor, :process, ^server, _reason} -> stop_subscription(pid)
    end
  end

  defp guard_subscription(_result, _server, monitor),
    do: Process.demonitor(monitor, [:flush])

  defp stop_subscription(nil), do: :ok

  defp stop_subscription(pid), do: safely(fn -> GenServer.stop(pid, :normal, :infinity) end)

  @impl true
  def handle_call({:joint_state, message}, _from, state) do
    {result, state} = update(message, state)
    {:reply, result, state}
  end

  @impl true
  def handle_cast({:joint_state, message}, state) do
    {_result, state} = update(message, state)
    {:noreply, state}
  end

  @impl true
  def handle_info({:DOWN, monitor, :process, _pid, reason}, %{monitor: monitor} = state),
    do: {:stop, {:node_down, reason}, state}

  @impl true
  def terminate(_reason, state), do: cleanup(state)

  defp update(message, state) do
    with {:ok, positions, stamp} <- validate_message(message),
         {:ok, transforms} <- Rclex.Urdf.transforms(state.model, positions, stamp, state.opts),
         {:ok, stamps} <- next_stamps(transforms.dynamic, stamp, state),
         :ok <- safely(fn -> broadcast(transforms.dynamic, :dynamic, state) end) do
      {:ok, %{state | stamps: stamps}}
    else
      {:error, _} = error -> {error, state}
    end
  end

  defp validate_message(%{name: names, position: positions, header: %{stamp: stamp}} = message)
       when is_list(names) and is_list(positions) do
    with :ok <- validate_joint_values(names, positions),
         :ok <- validate_optional_values(message, length(names)),
         true <- valid_stamp?(stamp) do
      {:ok, Map.new(Enum.zip(names, positions)), %{sec: stamp.sec, nanosec: stamp.nanosec}}
    else
      false -> {:error, :invalid_timestamp}
      error -> error
    end
  end

  defp validate_message(_), do: {:error, :invalid_joint_state}

  defp validate_joint_values(names, positions) do
    cond do
      length(names) != length(positions) ->
        {:error, :invalid_joint_state}

      not Enum.all?(names, &is_binary/1) ->
        {:error, :invalid_joint_names}

      length(Enum.uniq(names)) != length(names) ->
        {:error, :duplicate_joint_names}

      not Enum.all?(positions, &finite?/1) ->
        {:error, :invalid_positions}

      true ->
        :ok
    end
  end

  defp validate_optional_values(message, count) do
    cond do
      not valid_optional?(Map.get(message, :velocity, []), count) ->
        {:error, :invalid_velocity}

      not valid_optional?(Map.get(message, :effort, []), count) ->
        {:error, :invalid_effort}

      true ->
        :ok
    end
  end

  defp valid_optional?(values, count) when is_list(values),
    do: (values == [] or length(values) == count) and Enum.all?(values, &finite?/1)

  defp valid_optional?(_, _), do: false

  defp finite?(value) when is_number(value) do
    is_float(value * 1.0)
  rescue
    ArithmeticError -> false
  end

  defp finite?(_), do: false

  defp valid_stamp?(%{sec: sec, nanosec: nanosec}),
    do:
      is_integer(sec) and sec >= 0 and sec <= 2_147_483_647 and
        is_integer(nanosec) and nanosec >= 0 and nanosec < 1_000_000_000

  defp valid_stamp?(_), do: false

  defp next_stamps(transforms, stamp, state) do
    prefix = Keyword.get(state.opts, :frame_prefix, "")
    emitted = MapSet.new(transforms, & &1.child_frame_id)

    names =
      Enum.filter(state.model.joint_order, fn name ->
        MapSet.member?(emitted, prefix <> state.model.joints[name].child)
      end)

    timestamp = stamp.sec * 1_000_000_000 + stamp.nanosec

    case Enum.find(names, fn name -> timestamp < Map.get(state.stamps, name, -1) end) do
      nil -> {:ok, Enum.reduce(names, state.stamps, &Map.put(&2, &1, timestamp))}
      name -> {:error, {:backwards_stamp, name}}
    end
  end

  defp broadcast([], _kind, _state), do: :ok

  defp broadcast(transforms, kind, state) do
    messages = Enum.map(transforms, &transport_transform(&1, state.types))

    case kind do
      :static -> Rclex.Tf2.broadcast_static(messages, state.node_name, state.opts)
      :dynamic -> Rclex.Tf2.broadcast_dynamic(messages, state.node_name, state.opts)
    end
  end

  defp transport_transform(transform, types) do
    header =
      struct!(types.header, %{
        frame_id: transform.header.frame_id,
        stamp: struct!(types.time, transform.header.stamp)
      })

    geometry =
      struct!(types.transform, %{
        translation: struct!(types.vector3, transform.transform.translation),
        rotation: struct!(types.quaternion, transform.transform.rotation)
      })

    struct!(types.transform_stamped, %{
      header: header,
      child_frame_id: transform.child_frame_id,
      transform: geometry
    })
  end

  defp message_types do
    types =
      Map.new(
        [
          {:joint_state, "SensorMsgs", "JointState"},
          {:tf_message, "Tf2Msgs", "TFMessage"},
          {:header, "StdMsgs", "Header"},
          {:time, "BuiltinInterfaces", "Time"},
          {:transform_stamped, "GeometryMsgs", "TransformStamped"},
          {:transform, "GeometryMsgs", "Transform"},
          {:vector3, "GeometryMsgs", "Vector3"},
          {:quaternion, "GeometryMsgs", "Quaternion"}
        ],
        fn {key, package, name} ->
          {key, Module.concat(["Rclex", "Pkgs", package, "Msg", name])}
        end
      )

    case Enum.find(types, fn {_key, module} -> not Code.ensure_loaded?(module) end) do
      nil -> {:ok, types}
      {_key, module} -> {:error, {:message_type_not_generated, module}}
    end
  end

  defp validate_options(opts) do
    cond do
      not is_struct(opts[:model], Rclex.Urdf.Model) ->
        {:error, :invalid_model}

      not nonempty_binary?(opts[:node_name]) ->
        {:error, :invalid_node_name}

      Keyword.get(opts, :node_mode, :own) not in [:own, :borrow] ->
        {:error, :invalid_node_mode}

      not valid_namespace?(Keyword.get(opts, :namespace, "/")) ->
        {:error, :invalid_namespace}

      not nonempty_binary?(Keyword.get(opts, :joint_states_topic, "/joint_states")) ->
        {:error, :invalid_joint_states_topic}

      true ->
        :ok
    end
  end

  defp nonempty_binary?(value), do: is_binary(value) and value != ""

  defp valid_namespace?(value), do: is_binary(value) and String.starts_with?(value, "/")

  defp resolve_topic(opts) do
    topic = Keyword.get(opts, :joint_states_topic, "/joint_states")

    if String.starts_with?(topic, "/"),
      do: topic,
      else: Path.join(Keyword.get(opts, :namespace, "/"), topic)
  end

  defp cleanup(%{node_mode: :own} = state) do
    if state.monitor, do: Process.demonitor(state.monitor, [:flush])

    if state.node_supervisor_pid do
      safely(fn ->
        DynamicSupervisor.terminate_child(Rclex.NodesSupervisor, state.node_supervisor_pid)
      end)
    end

    :ok
  end

  defp cleanup(state) do
    if state.monitor, do: Process.demonitor(state.monitor, [:flush])
    stop_subscription(state.subscription_pid)
    :ok
  end

  defp safely(fun) do
    fun.()
  rescue
    exception -> {:error, {:transport_error, Exception.message(exception)}}
  catch
    :exit, reason -> {:error, {:transport_exit, reason}}
  end
end
