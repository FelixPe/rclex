defmodule Rclex.Tf2 do
  @moduledoc """
  ROS 2 transform buffers, listeners, broadcasters and stamped-geometry operations.

  The application automatically starts and supervises this module's registry.
  Buffers are created explicitly with `buffer_new/3`; they outlive their callers.
  Native `tf2::BufferCore` owns transform history, graph traversal and interpolation.
  Lookups access native resources directly rather than passing through the GenServer.
  ETS stores only the named-buffer registry. Listener/broadcaster metadata, clock
  bindings and pending asynchronous requests live in GenServer state; transport
  start/stop and buffer lifecycle operations are serialized there.

  A supervised cleanup owner retains native handles and tracks transport and
  accepted asynchronous requests. Graceful shutdown and abrupt registry death
  invalidate old native buffers, stop transport and complete pending requests
  with `{:error, :tf2_shutdown}`. A new registry generation waits for cleanup;
  buffers and transport must then be explicitly recreated.

  Buffers are scoped by identifier, node name and `:namespace` (default `"/"`).
  Query timestamps are integer nanoseconds; zero requests the latest transform.
  Wait deadlines use monotonic wall-time seconds, including when ROS time is paused.
  Fixed-frame query helpers accept `:timeout_sec` in their options.

  Set `error_details: true` to retain native errors as `{:error, {kind, message}}`.
  Asynchronous lookups return `{:ok, request_ref}` and send the caller
  `{:tf2_transform, request_ref, result}`. Use `cancel_wait/1` to cancel a pending request.

  A `:clock` option binds a new buffer to an `Rclex.Clock` server. Backward jumps and
  ROS-time activation changes clear dynamic history; static transforms survive.
  `clear/3` also preserves static transforms. Destroy the buffer to discard all data.

  Listeners and broadcasters use reliable QoS, with transient-local durability on
  `/tf_static`. Override profiles with `:tf_qos`, `:tf_static_qos` or the shared `:qos`.
  Native TF2 and generated `tf2_msgs/msg/TFMessage` support are required for transport.
  """

  use GenServer

  alias Rclex.Tf2.Cleanup

  @table :rclex_tf2_buffers
  @poll_ms 5
  @default_cache_time_sec 10.0

  @type buffer_name :: String.t() | atom()
  @type opts :: keyword()

  @doc false
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    Process.flag(:trap_exit, true)
    {:ok, cleanup} = Cleanup.attach()
    cleanup_monitor = Process.monitor(cleanup)
    new_table()

    {:ok,
     %{
       pending: %{},
       listeners: %{},
       broadcasters: %{},
       clocks: %{},
       cleanup_monitor: cleanup_monitor
     }}
  end

  @impl true
  def terminate(_reason, state) do
    if :ets.whereis(@table) != :undefined do
      Enum.each(:ets.tab2list(@table), fn {_key, resource} ->
        Rclex.Nif.tf2_buffer_destroy!(resource)
      end)
    end

    Enum.each(state.pending, fn {request, _wait} ->
      finish_wait(state, request, {:error, :tf2_shutdown})
    end)

    Enum.each(state.clocks, fn {resource, clock} ->
      safe_rclex_call(fn -> Rclex.Clock.unregister_tf2_buffer(clock, resource) end)
    end)

    Enum.each(state.listeners, fn {_key, transport} -> stop_transport(:listener, transport) end)

    Enum.each(state.broadcasters, fn {_key, transport} ->
      stop_transport(:broadcaster, transport)
    end)

    safe_rclex_call(fn -> Cleanup.release() end)
    :ok
  end

  @impl true
  def handle_call({:buffer_new, buffer_key, opts}, _from, state) do
    {result, state} =
      case :ets.lookup(@table, buffer_key) do
        [] -> create_buffer(buffer_key, opts, state)
        _ -> {:ok, state}
      end

    {:reply, result, state}
  end

  def handle_call(
        {:buffer_destroy, {buffer_name, name, _namespace} = buffer_key, opts},
        _from,
        state
      ) do
    {_result, state} = do_stop_listener(buffer_name, name, opts, state)
    {_result, state} = do_stop_broadcaster(name, opts, state)

    case :ets.take(@table, buffer_key) do
      [] ->
        {:reply, {:error, :buffer_not_found}, state}

      [{_, resource}] ->
        state = unbind_clock(resource, state)
        result = Cleanup.buffer_destroy(resource)

        state =
          Enum.reduce(state.pending, state, fn {request, wait}, acc ->
            finish_buffer_wait(acc, resource, request, wait)
          end)

        {:reply, result, state}
    end
  end

  def handle_call(:ensure_table, _from, state) do
    new_table()
    {:reply, :ok, state}
  end

  def handle_call({:start_listener, buffer_name, name, opts}, _from, state) do
    {result, state} = do_start_listener(buffer_name, name, opts, state)
    {:reply, result, state}
  end

  def handle_call({:stop_listener, buffer_name, name, opts}, _from, state) do
    {result, state} = do_stop_listener(buffer_name, name, opts, state)
    {:reply, result, state}
  end

  def handle_call({:start_broadcaster, name, opts}, _from, state) do
    {result, state} = do_start_broadcaster(name, opts, state)
    {:reply, result, state}
  end

  def handle_call({:stop_broadcaster, name, opts}, _from, state) do
    {result, state} = do_stop_broadcaster(name, opts, state)
    {:reply, result, state}
  end

  def handle_call({:wait, buffer_key, args, timeout, opts}, {caller, _tag}, state) do
    case fetch_buffer(buffer_key) do
      {:ok, resource} ->
        request = make_ref()

        case apply(Rclex.Nif, :tf2_lookup_transform!, [resource | args]) do
          {:error, {kind, _}}
          when kind in [
                 :lookup,
                 :connectivity,
                 :extrapolation,
                 :extrapolation_past,
                 :extrapolation_future
               ] ->
            :ok = Cleanup.register_wait(request, caller)

            wait = %{
              resource: resource,
              args: args,
              caller: caller,
              opts: opts,
              monitor: Process.monitor(caller),
              timer: Process.send_after(self(), {:wait_timeout, request}, trunc(timeout * 1_000))
            }

            {:reply, {:ok, request}, %{state | pending: Map.put(state.pending, request, wait)}}

          result ->
            send(caller, {:tf2_transform, request, native_result(result, opts)})
            {:reply, {:ok, request}, state}
        end

      error ->
        {:reply, error, state}
    end
  end

  def handle_call({:cancel_wait, request}, {caller, _tag}, state) do
    case Map.get(state.pending, request) do
      %{caller: ^caller} -> {:reply, :ok, finish_wait(state, request, nil)}
      _ -> {:reply, {:error, :wait_not_found}, state}
    end
  end

  @impl true
  def handle_cast({:new_transform, resource}, state) do
    state =
      Enum.reduce(state.pending, state, fn {request, wait}, acc ->
        recheck_wait(acc, resource, request, wait)
      end)

    {:noreply, state}
  end

  @impl true
  def handle_info({:wait_timeout, request}, state) do
    {:noreply, finish_wait(state, request, {:error, :timeout})}
  end

  def handle_info({:DOWN, monitor, :process, _pid, reason}, %{cleanup_monitor: monitor} = state) do
    {:stop, {:cleanup_process_down, reason}, state}
  end

  def handle_info({:DOWN, monitor, :process, _pid, _reason}, state) do
    state =
      Enum.reduce(state.pending, state, fn {request, wait}, acc ->
        if wait.monitor == monitor, do: finish_wait(acc, request, nil), else: acc
      end)

    {:noreply, state}
  end

  defp finish_wait(state, request, result) do
    case Map.pop(state.pending, request) do
      {nil, _} ->
        state

      {wait, pending} ->
        Process.cancel_timer(wait.timer)
        Process.demonitor(wait.monitor, [:flush])

        complete_wait(request, wait, result)

        %{state | pending: pending}
    end
  end

  defp complete_wait(request, wait, result) do
    result = if result, do: native_result(result, wait.opts)

    case Cleanup.finish_wait(request, result) do
      :ok ->
        :ok

      {:error, :tf2_shutdown} ->
        if result, do: send(wait.caller, {:tf2_transform, request, result})
    end
  catch
    :exit, _ ->
      if result,
        do: send(wait.caller, {:tf2_transform, request, native_result(result, wait.opts)})
  end

  defp finish_buffer_wait(state, resource, request, %{resource: resource}) do
    finish_wait(state, request, {:error, :buffer_not_found})
  end

  defp finish_buffer_wait(state, _resource, _request, _wait), do: state

  defp recheck_wait(state, resource, request, %{resource: resource} = wait) do
    case apply(Rclex.Nif, :tf2_lookup_transform!, [resource | wait.args]) do
      {:ok, _} = result -> finish_wait(state, request, result)
      _ -> state
    end
  end

  defp recheck_wait(state, _resource, _request, _wait), do: state

  defp create_buffer(buffer_key, opts, state) do
    cache_time = Keyword.get(opts, :cache_time_sec, @default_cache_time_sec)
    create_buffer(buffer_key, opts, cache_time, state)
  end

  defp create_buffer(buffer_key, opts, cache_time, state)
       when is_number(cache_time) and cache_time >= 0 do
    case Cleanup.buffer_new(trunc(cache_time * 1_000_000_000)) do
      {:ok, resource} ->
        case bind_clock(resource, opts, state) do
          {:ok, state} ->
            :ets.insert(@table, {buffer_key, resource})
            {:ok, state}

          {error, state} ->
            Cleanup.buffer_destroy(resource)
            {error, state}
        end

      error ->
        {error, state}
    end
  end

  defp create_buffer(_buffer_key, _opts, _cache_time, state),
    do: {{:error, :invalid_cache_time}, state}

  defp new_table do
    if :ets.whereis(@table) == :undefined do
      :ets.new(@table, [
        :named_table,
        :public,
        :set,
        read_concurrency: true,
        write_concurrency: true
      ])
    end
  end

  defp bind_clock(resource, opts, state) do
    case Keyword.get(opts, :clock) do
      nil ->
        {:ok, state}

      server ->
        case GenServer.whereis(server) do
          nil ->
            {{:error, :clock_not_found}, state}

          pid ->
            :ok = Rclex.Clock.register_tf2_buffer(pid, resource)
            {:ok, %{state | clocks: Map.put(state.clocks, resource, pid)}}
        end
    end
  catch
    :exit, _ -> {{:error, :clock_not_found}, state}
  end

  defp unbind_clock(resource, state) do
    {clock, clocks} = Map.pop(state.clocks, resource)
    if clock, do: safe_rclex_call(fn -> Rclex.Clock.unregister_tf2_buffer(clock, resource) end)
    %{state | clocks: clocks}
  end

  @doc ~S"""
  Create a TF2 buffer identified by `buffer_name` for a node.

  This buffer stores dynamic and static transforms and is queried by frame names.
  Storage, graph traversal and interpolation use the installed ROS 2 C++
  `tf2::BufferCore`. The buffer outlives the process creating it.

  ### Parameters

  - `buffer_name` - Public identifier for the TF buffer (for example `"main"`).
  - `name` - Node name used to scope the buffer owner.

  ### opts

  - `:namespace` must lead with "/". if not specified, the default is "/"
  - `:cache_time_sec` cache duration for dynamic transforms in seconds (`float`), default `10.0`.
  - `:clock` optional `Rclex.Clock` server. Backward jumps and ROS-time activation
    changes clear dynamic history, preserving static transforms.

  ### Examples

      iex> Rclex.Tf2.buffer_new("main", "node", namespace: "/robot")
      :ok
  """
  @spec buffer_new(buffer_name(), String.t(), opts()) :: :ok | {:error, term()}
  def buffer_new(buffer_name, name, opts \\ [])
      when (is_binary(buffer_name) or is_atom(buffer_name)) and is_binary(name) and is_list(opts) do
    GenServer.call(__MODULE__, {:buffer_new, key(buffer_name, name, opts), opts})
  end

  @doc ~S"""
  Destroy a TF2 buffer identified by `buffer_name` for a node.

  ### Parameters

  - `buffer_name` - Buffer identifier passed to `buffer_new/3`.
  - `name` - Node name used when creating the buffer.

  ### opts

  - `:namespace` must lead with "/". if not specified, the default is "/"

  ### Examples

      iex> Rclex.Tf2.buffer_destroy("main", "node", namespace: "/robot")
      :ok
  """
  @spec buffer_destroy(buffer_name(), String.t(), opts()) :: :ok | {:error, term()}
  def buffer_destroy(buffer_name, name, opts \\ [])
      when (is_binary(buffer_name) or is_atom(buffer_name)) and is_binary(name) and is_list(opts) do
    GenServer.call(__MODULE__, {:buffer_destroy, key(buffer_name, name, opts), opts})
  end

  @doc ~S"""
  Clear dynamic TF2 history from a buffer.

  Matches native `tf2::BufferCore.clear()`: static transforms and registered frame
  names survive. Destroy and recreate the buffer to discard all data.

  ### Parameters

  - `buffer_name` - Buffer identifier.
  - `name` - Node name used to resolve the buffer.

  ### opts

  - `:namespace` must lead with "/". if not specified, the default is "/"

  ### Examples

      iex> Rclex.Tf2.clear("main", "node", namespace: "/robot")
      :ok
  """
  @spec clear(buffer_name(), String.t(), opts()) :: :ok | {:error, term()}
  def clear(buffer_name, name, opts \\ [])
      when (is_binary(buffer_name) or is_atom(buffer_name)) and is_binary(name) and is_list(opts) do
    ensure_table!()
    key = key(buffer_name, name, opts)

    with {:ok, buffer} <- fetch_buffer(key) do
      Rclex.Nif.tf2_clear!(buffer) |> native_result(opts)
    end
  end

  @type frame_info :: %{
          child: String.t(),
          parent: String.t(),
          broadcaster: String.t(),
          rate: float(),
          most_recent_transform: float(),
          oldest_transform: float(),
          buffer_length: float()
        }

  @doc ~S"""
  Return known TF2 frames as structured data.

  Each entry describes one child frame: its parent, broadcaster authority,
  update rate, latest/oldest transform time, and buffer length. This is the
  same data `all_frames_as_yaml/3` renders to text — use this instead when
  a caller wants to consume the frame graph programmatically (for example, to
  draw it) rather than parse YAML meant for diagnostics.

  ### Parameters

  - `buffer_name` - Buffer identifier.
  - `name` - Node name used to resolve the buffer.

  ### opts

  - `:namespace` must lead with "/". if not specified, the default is "/"

  ### Examples

      iex> {:ok, frames} = Rclex.Tf2.list_frames("main", "node")
      iex> is_list(frames)
      true
  """
  @spec list_frames(buffer_name(), String.t(), opts()) ::
          {:ok, [frame_info()]} | {:error, term()}
  def list_frames(buffer_name, name, opts \\ [])
      when (is_binary(buffer_name) or is_atom(buffer_name)) and is_binary(name) and is_list(opts) do
    ensure_table!()
    key = key(buffer_name, name, opts)

    with {:ok, buffer} <- fetch_buffer(key) do
      Rclex.Nif.tf2_list_frames!(buffer) |> native_result(opts)
    end
  end

  @doc ~S"""
  Return known TF2 frames as YAML.

  The output is intended for diagnostics and mirrors the common TF2 frame-graph
  style: entries include parent frame, broadcaster, rate, latest/oldest
  transform time, and buffer length.

  ### Parameters

  - `buffer_name` - Buffer identifier.
  - `name` - Node name used to resolve the buffer.

  ### opts

  - `:namespace` must lead with "/". if not specified, the default is "/"

  ### Examples

      iex> {:ok, yaml} = Rclex.Tf2.all_frames_as_yaml("main", "node")
      iex> is_binary(yaml)
      true
  """
  @spec all_frames_as_yaml(buffer_name(), String.t(), opts()) ::
          {:ok, String.t()} | {:error, term()}
  def all_frames_as_yaml(buffer_name, name, opts \\ [])
      when (is_binary(buffer_name) or is_atom(buffer_name)) and is_binary(name) and is_list(opts) do
    ensure_table!()

    with {:ok, buffer} <- fetch_buffer(key(buffer_name, name, opts)) do
      Rclex.Nif.tf2_all_frames_as_yaml!(buffer) |> native_result(opts)
    end
  end

  @doc ~S"""
  Return latest common timestamp (ns) between two frames.

  This follows the TF2 "latest common time" concept and is useful when
  performing `time_ns = 0` (latest) lookups.

  ### Parameters

  - `buffer_name` - Buffer identifier.
  - `target_frame` - Destination frame.
  - `source_frame` - Source frame.
  - `name` - Node name used to resolve the buffer.

  ### opts

  - `:namespace` must lead with "/". if not specified, the default is "/"

  ### Examples

      iex> {:ok, ns} = Rclex.Tf2.get_latest_common_time("main", "map", "base_link", "node")
      iex> is_integer(ns)
      true
  """
  @spec get_latest_common_time(buffer_name(), String.t(), String.t(), String.t(), opts()) ::
          {:ok, integer()} | {:error, term()}
  def get_latest_common_time(buffer_name, target_frame, source_frame, name, opts \\ [])
      when (is_binary(buffer_name) or is_atom(buffer_name)) and is_binary(target_frame) and
             is_binary(source_frame) and is_binary(name) and is_list(opts) do
    ensure_table!()
    key = key(buffer_name, name, opts)

    with {:ok, buffer} <- fetch_buffer(key),
         :ok <- validate_frame_ids(target_frame, source_frame) do
      Rclex.Nif.tf2_get_latest_common_time!(buffer, target_frame, source_frame)
      |> native_result(opts)
    end
  end

  @doc ~S"""
    Insert or update a TF2 transform in the buffer.

  Dynamic transforms are time-aware and can be interpolated for lookup queries.

  ### Parameters

  - `buffer_name` - Buffer identifier.
  - `transform_stamped` - Map/struct compatible with `geometry_msgs/TransformStamped` shape.
  - `authority` - Optional broadcaster identifier for diagnostics.
  - `name` - Node name used to resolve the buffer.

  ### opts

  - `:namespace` must lead with "/". if not specified, the default is "/"

  ### Examples

      iex> ts = %{
      ...>   header: %{frame_id: "map", stamp: %{sec: 10, nanosec: 0}},
      ...>   child_frame_id: "base_link",
      ...>   transform: %{
      ...>     translation: %{x: 1.0, y: 0.0, z: 0.0},
      ...>     rotation: %{w: 1.0, x: 0.0, y: 0.0, z: 0.0}
      ...>   }
      ...> }
      iex> Rclex.Tf2.set_transform("main", ts, "odometry", "node", namespace: "/robot")
      :ok
  """
  @spec set_transform(buffer_name(), map() | struct(), String.t(), String.t(), opts()) ::
          :ok | {:error, term()}
  def set_transform(buffer_name, transform_stamped, authority \\ "", name, opts \\ [])
      when (is_binary(buffer_name) or is_atom(buffer_name)) and
             (is_map(transform_stamped) or is_struct(transform_stamped)) and is_binary(authority) and
             is_binary(name) and is_list(opts) do
    ensure_table!()
    key = key(buffer_name, name, opts)

    with {:ok, buffer} <- fetch_buffer(key),
         {:ok, edge} <- extract_edge(transform_stamped),
         {:ok, stamp_ns} <- extract_stamp_ns(transform_stamped),
         {:ok, normalized_tf} <- normalize_transform(transform_stamped),
         :ok <- validate_quaternion(normalized_tf.rotation) do
      Rclex.Nif.tf2_set_transform!(
        buffer,
        native_transform(edge, stamp_ns, normalized_tf),
        authority,
        false
      )
      |> notify_transform(buffer)
      |> native_result(opts)
    end
  end

  @doc ~S"""
  Insert or update a static TF2 transform in the buffer.

  Static transforms are treated as valid across time and are not subject to
  dynamic cache extrapolation behavior.

  ### Parameters

  - `buffer_name` - Buffer identifier.
  - `transform_stamped` - Map/struct compatible with `geometry_msgs/TransformStamped` shape.
  - `authority` - Optional broadcaster identifier for diagnostics.
  - `name` - Node name used to resolve the buffer.

  ### opts

  - `:namespace` must lead with "/". if not specified, the default is "/"

  ### Examples

      iex> ts = %{
      ...>   header: %{frame_id: "base_link", stamp: %{sec: 0, nanosec: 0}},
      ...>   child_frame_id: "camera_link",
      ...>   transform: %{
      ...>     translation: %{x: 0.2, y: 0.0, z: 0.1},
      ...>     rotation: %{w: 1.0, x: 0.0, y: 0.0, z: 0.0}
      ...>   }
      ...> }
      iex> Rclex.Tf2.set_transform_static("main", ts, "urdf", "node")
      :ok
  """
  @spec set_transform_static(buffer_name(), map() | struct(), String.t(), String.t(), opts()) ::
          :ok | {:error, term()}
  def set_transform_static(buffer_name, transform_stamped, authority \\ "", name, opts \\ [])
      when (is_binary(buffer_name) or is_atom(buffer_name)) and
             (is_map(transform_stamped) or is_struct(transform_stamped)) and is_binary(authority) and
             is_binary(name) and is_list(opts) do
    ensure_table!()
    key = key(buffer_name, name, opts)

    with {:ok, buffer} <- fetch_buffer(key),
         {:ok, edge} <- extract_edge(transform_stamped),
         {:ok, stamp_ns} <- extract_stamp_ns(transform_stamped),
         {:ok, normalized_tf} <- normalize_transform(transform_stamped),
         :ok <- validate_quaternion(normalized_tf.rotation) do
      Rclex.Nif.tf2_set_transform!(
        buffer,
        native_transform(edge, stamp_ns, normalized_tf),
        authority,
        true
      )
      |> notify_transform(buffer)
      |> native_result(opts)
    end
  end

  @doc ~S"""
  Check whether a TF2 transform is available within timeout.

  `timeout_sec` is in seconds (`float`).

  `time_ns` semantics:

  - `0` => latest common time lookup
  - `> 0` => lookup at specific timestamp (ns)

  ### Parameters

  - `buffer_name` - Buffer identifier.
  - `target_frame` - Destination frame.
  - `source_frame` - Source frame.
  - `time_ns` - Query timestamp in nanoseconds (`0` means latest).
  - `timeout_sec` - Maximum wait duration in seconds.
  - `name` - Node name used to resolve the buffer.

  ### opts

  - `:namespace` must lead with "/". if not specified, the default is "/"
  - `:return_debug_tuple` when `true`, returns `{boolean, reason}`.

  ### Examples

      iex> Rclex.Tf2.can_transform?("main", "map", "base_link", 0, 0.1, "node")
      true

      iex> Rclex.Tf2.can_transform?("main", "map", "unknown", 0, 0.0, "node", return_debug_tuple: true)
      {false, "frame connectivity failed"}
  """
  @spec can_transform?(
          buffer_name(),
          String.t(),
          String.t(),
          integer(),
          float(),
          String.t(),
          opts()
        ) :: boolean() | {boolean(), String.t()} | {:error, term()}
  def can_transform?(
        buffer_name,
        target_frame,
        source_frame,
        time_ns,
        timeout_sec \\ 0.0,
        name,
        opts \\ []
      )
      when (is_binary(buffer_name) or is_atom(buffer_name)) and is_binary(target_frame) and
             is_binary(source_frame) and is_integer(time_ns) and is_number(timeout_sec) and
             is_binary(name) and is_list(opts) do
    ensure_table!()
    key = key(buffer_name, name, opts)
    return_debug_tuple = Keyword.get(opts, :return_debug_tuple, false)

    with {:ok, _} <- fetch_buffer(key) do
      query(key, :can_transform, [target_frame, source_frame, time_ns], timeout_sec)
      |> can_transform_result(return_debug_tuple)
    end
  end

  defp can_transform_result({:ok, true}, true), do: {true, ""}
  defp can_transform_result({:ok, true}, false), do: true
  defp can_transform_result({:error, reason}, true), do: {false, reason_to_string(reason)}
  defp can_transform_result({:error, _reason}, false), do: false

  @doc ~S"""
  Lookup a TF2 transform within timeout.

  `timeout_sec` is in seconds (`float`).

  `time_ns` semantics:

  - `0` => latest common time lookup
  - `> 0` => lookup at specific timestamp (ns)

  Set `error_details: true` to retain the upstream message as `{:error, {kind, message}}`.
  Native versions may return `:extrapolation` when insufficient history prevents a
  more specific classification. Timeouts use monotonic wall time, even with paused ROS time.

  Possible errors include connectivity and extrapolation (`:extrapolation_past`
  or `:extrapolation_future`) depending on the query time and cached data.

  ### Parameters

  - `buffer_name` - Buffer identifier.
  - `target_frame` - Destination frame.
  - `source_frame` - Source frame.
  - `time_ns` - Query timestamp in nanoseconds (`0` means latest).
  - `timeout_sec` - Maximum wait duration in seconds.
  - `name` - Node name used to resolve the buffer.

  ### opts

  - `:namespace` must lead with "/". if not specified, the default is "/"

  ### Examples

      iex> {:ok, tf} =
      ...>   Rclex.Tf2.lookup_transform(
      ...>     "main",
      ...>     "map",
      ...>     "base_link",
      ...>     0,
      ...>     0.1,
      ...>     "node",
      ...>     namespace: "/robot"
      ...>   )
      iex> tf.header.frame_id
      "map"
  """
  @spec lookup_transform(
          buffer_name(),
          String.t(),
          String.t(),
          integer(),
          float(),
          String.t(),
          opts()
        ) :: {:ok, map()} | {:error, term()}
  def lookup_transform(
        buffer_name,
        target_frame,
        source_frame,
        time_ns,
        timeout_sec \\ 0.0,
        name,
        opts \\ []
      )
      when (is_binary(buffer_name) or is_atom(buffer_name)) and is_binary(target_frame) and
             is_binary(source_frame) and is_integer(time_ns) and is_number(timeout_sec) and
             is_binary(name) and is_list(opts) do
    ensure_table!()
    key = key(buffer_name, name, opts)

    query(key, :lookup_transform, [target_frame, source_frame, time_ns], timeout_sec)
    |> native_result(opts)
  end

  @doc ~S"""
  Looks up a transform using separate source and target times through a fixed frame.

  Times are nanoseconds; zero requests the latest available time. Native tf2 errors
  are returned as atoms, or `{:error, {kind, message}}` with `error_details: true`.
  Set `timeout_sec: seconds` in options to wait (default `0.0`). This is a monotonic
  wall-time deadline and does not block a BEAM scheduler.
  """
  @spec lookup_transform_full(
          buffer_name(),
          String.t(),
          integer(),
          String.t(),
          integer(),
          String.t(),
          String.t(),
          opts()
        ) :: {:ok, map()} | {:error, term()}
  def lookup_transform_full(
        buffer_name,
        target,
        target_time,
        source,
        source_time,
        fixed,
        name,
        opts \\ []
      ) do
    ensure_table!()

    query(
      key(buffer_name, name, opts),
      :lookup_transform,
      [target, target_time, source, source_time, fixed],
      Keyword.get(opts, :timeout_sec, 0.0)
    )
    |> native_result(opts)
  end

  @doc ~S"""
  Checks transform availability using separate source and target times through a fixed frame.

  Set `return_debug_tuple: true` to receive `{available?, upstream_reason}`.
  Set `timeout_sec: seconds` to wait for availability (default `0.0`).
  """
  @spec can_transform_full?(
          buffer_name(),
          String.t(),
          integer(),
          String.t(),
          integer(),
          String.t(),
          String.t(),
          opts()
        ) :: boolean() | {boolean(), String.t()} | {:error, term()}
  def can_transform_full?(
        buffer_name,
        target,
        target_time,
        source,
        source_time,
        fixed,
        name,
        opts \\ []
      ) do
    ensure_table!()

    with {:ok, _} <- fetch_buffer(key(buffer_name, name, opts)) do
      query(
        key(buffer_name, name, opts),
        :can_transform,
        [target, target_time, source, source_time, fixed],
        Keyword.get(opts, :timeout_sec, 0.0)
      )
      |> can_transform_result(Keyword.get(opts, :return_debug_tuple, false))
    end
  end

  @doc ~S"""
  Waits asynchronously for a native TF2 lookup.

  Returns `{:ok, request_ref}` and delivers `{:tf2_transform, request_ref, result}`
  to the caller. The timeout is in monotonic wall-time seconds, including when
  ROS time is paused. Pending requests are removed when the caller exits.
  Registry shutdown or restart completes accepted requests with
  `{:error, :tf2_shutdown}` rather than leaving callers waiting.
  """
  @spec lookup_transform_async(
          buffer_name(),
          String.t(),
          String.t(),
          integer(),
          number(),
          String.t(),
          opts()
        ) ::
          {:ok, reference()} | {:error, term()}
  def lookup_transform_async(
        buffer_name,
        target,
        source,
        time_ns,
        timeout_sec \\ 5.0,
        name,
        opts \\ []
      ) do
    start_wait(buffer_name, [target, source, time_ns], timeout_sec, name, opts)
  end

  @doc ~S"""
  Waits asynchronously for a lookup with separate source and target times through a fixed frame.

  Uses the same reply message and cancellation contract as `lookup_transform_async/7`.
  Configure the deadline with `timeout_sec: seconds` in options (default `5.0`).
  """
  @spec lookup_transform_full_async(
          buffer_name(),
          String.t(),
          integer(),
          String.t(),
          integer(),
          String.t(),
          String.t(),
          opts()
        ) :: {:ok, reference()} | {:error, term()}
  def lookup_transform_full_async(
        buffer_name,
        target,
        target_time,
        source,
        source_time,
        fixed,
        name,
        opts \\ []
      ) do
    start_wait(
      buffer_name,
      [target, target_time, source, source_time, fixed],
      Keyword.get(opts, :timeout_sec, 5.0),
      name,
      opts
    )
  end

  defp start_wait(buffer_name, args, timeout_sec, name, opts) do
    if is_number(timeout_sec) and timeout_sec >= 0 and timeout_sec <= 4_294_967 do
      GenServer.call(__MODULE__, {:wait, key(buffer_name, name, opts), args, timeout_sec, opts})
    else
      {:error, :invalid_timeout}
    end
  end

  @doc ~S"""
  Cancels a pending TF2 wait owned by the caller.

  Returns `:ok` if cancelled, or `{:error, :wait_not_found}` if it already completed,
  was cancelled, or belongs to another process. A reply already delivered is not retracted.
  """
  @spec cancel_wait(reference()) :: :ok | {:error, :wait_not_found}
  def cancel_wait(request), do: GenServer.call(__MODULE__, {:cancel_wait, request})

  defp notify_transform(:ok, buffer) do
    GenServer.cast(__MODULE__, {:new_transform, buffer})
    :ok
  end

  defp notify_transform(result, _buffer), do: result

  @doc ~S"""
  Start TF topic listeners for `/tf` and `/tf_static` and feed incoming transforms
  into the specified TF2 buffer.

  This is the ROS transport counterpart to `set_transform/5` and
  `set_transform_static/5`.

  ### Parameters

  - `buffer_name` - TF2 buffer identifier.
  - `name` - Node name that owns the subscriptions.

  ### opts

  - `:namespace` must lead with "/". if not specified, the default is "/"
  - `:authority` authority string attached to ingested transforms (default `"tf_listener"`).
  - `:tf_message_type_module` overrides the generated `tf2_msgs/msg/TFMessage` module.

  ### Notes

  Requires generated message type `tf2_msgs/msg/TFMessage`.
  """
  @spec start_listener(buffer_name(), String.t(), opts()) :: :ok | {:error, term()}
  def start_listener(buffer_name, name, opts \\ [])
      when (is_binary(buffer_name) or is_atom(buffer_name)) and is_binary(name) and is_list(opts) do
    GenServer.call(__MODULE__, {:start_listener, buffer_name, name, opts})
  end

  defp do_start_listener(buffer_name, name, opts, state) do
    authority = Keyword.get(opts, :authority, "tf_listener")

    with :ok <- ensure_tf_message_type_available(opts),
         {:ok, _} <- fetch_buffer(key(buffer_name, name, opts)),
         {:ok, state} <- ensure_subscription(:tf, buffer_name, name, authority, opts, state) do
      ensure_subscription(:tf_static, buffer_name, name, authority, opts, state)
    else
      {:error, _} = error -> {error, state}
      {error, state} -> {error, state}
    end
  end

  @doc ~S"""
  Stop TF topic listeners (`/tf`, `/tf_static`) for the given buffer and node.

  ### opts

  - `:namespace` must lead with "/". if not specified, the default is "/"
  - `:tf_message_type_module` overrides the generated `tf2_msgs/msg/TFMessage` module.
  """
  @spec stop_listener(buffer_name(), String.t(), opts()) :: :ok | {:error, term()}
  def stop_listener(buffer_name, name, opts \\ [])
      when (is_binary(buffer_name) or is_atom(buffer_name)) and is_binary(name) and is_list(opts) do
    GenServer.call(__MODULE__, {:stop_listener, buffer_name, name, opts})
  end

  defp do_stop_listener(buffer_name, name, opts, state) do
    case ensure_tf_message_type_available(opts) do
      :ok ->
        tf_message_type = tf_message_type_module(opts)

        buffer_key = key(buffer_name, name, opts)

        for topic_kind <- [:tf, :tf_static] do
          transport =
            Map.get(state.listeners, {buffer_key, topic_kind}, %{
              message_type: tf_message_type,
              topic: topic_name(topic_kind),
              name: name,
              opts: opts
            })

          stop_transport(:listener, transport)
        end

        listeners =
          state.listeners
          |> Map.delete({buffer_key, :tf})
          |> Map.delete({buffer_key, :tf_static})

        {:ok, %{state | listeners: listeners}}

      error ->
        {error, state}
    end
  end

  @doc ~S"""
  Start TF topic publishers for `/tf` and `/tf_static`.

  ### Parameters

  - `name` - Node name that owns the publishers.

  ### opts

  - `:namespace` must lead with "/". if not specified, the default is "/"
  - `:tf_message_type_module` overrides the generated `tf2_msgs/msg/TFMessage` module.
  """
  @spec start_broadcaster(String.t(), opts()) :: :ok | {:error, term()}
  def start_broadcaster(name, opts \\ []) when is_binary(name) and is_list(opts) do
    GenServer.call(__MODULE__, {:start_broadcaster, name, opts})
  end

  defp do_start_broadcaster(name, opts, state) do
    with :ok <- ensure_tf_message_type_available(opts),
         {:ok, state} <- ensure_publisher(:tf, name, opts, state) do
      ensure_publisher(:tf_static, name, opts, state)
    else
      {:error, _} = error -> {error, state}
      {error, state} -> {error, state}
    end
  end

  @doc ~S"""
  Stop TF topic publishers for `/tf` and `/tf_static`.

  ### opts

  - `:namespace` must lead with "/". if not specified, the default is "/"
  - `:tf_message_type_module` overrides the generated `tf2_msgs/msg/TFMessage` module.
  """
  @spec stop_broadcaster(String.t(), opts()) :: :ok | {:error, term()}
  def stop_broadcaster(name, opts \\ []) when is_binary(name) and is_list(opts) do
    GenServer.call(__MODULE__, {:stop_broadcaster, name, opts})
  end

  defp do_stop_broadcaster(name, opts, state) do
    case ensure_tf_message_type_available(opts) do
      :ok ->
        tf_message_type = tf_message_type_module(opts)
        namespace = Keyword.get(opts, :namespace, "/")

        for topic_kind <- [:tf, :tf_static] do
          transport =
            Map.get(state.broadcasters, {name, namespace, topic_kind}, %{
              message_type: tf_message_type,
              topic: topic_name(topic_kind),
              name: name,
              opts: opts
            })

          stop_transport(:broadcaster, transport)
        end

        broadcasters =
          state.broadcasters
          |> Map.delete({name, namespace, :tf})
          |> Map.delete({name, namespace, :tf_static})

        {:ok, %{state | broadcasters: broadcasters}}

      error ->
        {error, state}
    end
  end

  defp safe_rclex_call(fun) do
    try do
      fun.()
    catch
      :exit, _ -> :ok
    end
  end

  defp stop_transport(kind, transport) do
    case Cleanup.stop_transport(kind, transport) do
      {:error, :tf2_shutdown} -> Cleanup.stop_endpoint(kind, transport)
      result -> result
    end
  catch
    :exit, _ -> Cleanup.stop_endpoint(kind, transport)
  end

  @doc ~S"""
  Publish one or more dynamic transforms to `/tf`.

  ### Parameters

  - `transform_stamped_or_list` - A `TransformStamped`-compatible map/struct or a list of them.
  - `name` - Node name that owns the publisher.

  ### opts

  - `:namespace` must lead with "/". if not specified, the default is "/"
  - `:tf_message_type_module` overrides the generated `tf2_msgs/msg/TFMessage` module.
  """
  @spec broadcast_dynamic([map() | struct()] | map() | struct(), String.t(), opts()) ::
          :ok | {:error, term()}
  def broadcast_dynamic(transform_stamped_or_list, name, opts \\ [])
      when (is_map(transform_stamped_or_list) or is_struct(transform_stamped_or_list) or
              is_list(transform_stamped_or_list)) and is_binary(name) and is_list(opts) do
    publish_tf_message(transform_stamped_or_list, "/tf", name, opts)
  end

  @doc ~S"""
  Publish one or more static transforms to `/tf_static`.

  ### Parameters

  - `transform_stamped_or_list` - A `TransformStamped`-compatible map/struct or a list of them.
  - `name` - Node name that owns the publisher.

  ### opts

  - `:namespace` must lead with "/". if not specified, the default is "/"
  - `:tf_message_type_module` overrides the generated `tf2_msgs/msg/TFMessage` module.
  """
  @spec broadcast_static([map() | struct()] | map() | struct(), String.t(), opts()) ::
          :ok | {:error, term()}
  def broadcast_static(transform_stamped_or_list, name, opts \\ [])
      when (is_map(transform_stamped_or_list) or is_struct(transform_stamped_or_list) or
              is_list(transform_stamped_or_list)) and is_binary(name) and is_list(opts) do
    publish_tf_message(transform_stamped_or_list, "/tf_static", name, opts)
  end

  defp query(buffer_key, operation, args, timeout_sec) do
    with {:ok, buffer} <- fetch_buffer(buffer_key),
         :ok <- validate_query_frames(operation, args) do
      wait_until(deadline_ms(timeout_sec), fn -> native_probe(operation, buffer, args) end)
    end
  end

  defp validate_query_frames(:lookup_transform, [target, source, _time]),
    do: validate_frame_ids(target, source)

  defp validate_query_frames(:lookup_transform, [
         target,
         _target_time,
         source,
         _source_time,
         _fixed
       ]),
       do: validate_frame_ids(target, source)

  defp validate_query_frames(:can_transform, _args), do: :ok

  defp native_probe(operation, buffer, args) do
    function =
      if operation == :lookup_transform, do: :tf2_lookup_transform!, else: :tf2_can_transform!

    case apply(Rclex.Nif, function, [buffer | args]) do
      {true, _message} -> {:ok, true}
      {false, message} -> {:retry, message}
      {:error, reason} -> {:retry, reason}
      result -> result
    end
  end

  defp native_transform({parent, child}, stamp_ns, %{translation: translation, rotation: rotation}) do
    {parent, child, stamp_ns, {translation.x, translation.y, translation.z},
     {rotation.x, rotation.y, rotation.z, rotation.w}}
  end

  defp native_result({:error, {kind, _message}} = result, opts) do
    if Keyword.get(opts, :error_details, false), do: result, else: {:error, kind}
  end

  defp native_result(result, _opts), do: result

  @doc ~S"""
  Transforms a stamped geometry message using native `tf2_geometry_msgs` operations.

  Supports PointStamped, Vector3Stamped, QuaternionStamped, PoseStamped and
  TransformStamped shapes. Accepts atom-keyed maps or generated message structs
  and preserves their struct types. The input header specifies source frame and time.
  """
  @spec transform(buffer_name(), map() | struct(), String.t(), String.t(), opts()) ::
          {:ok, map() | struct()} | {:error, term()}
  def transform(buffer_name, message, target, name, opts \\ []) do
    ensure_table!()

    with {:ok, buffer} <- fetch_buffer(key(buffer_name, name, opts)),
         {:ok, kind} <- geometry_kind(message),
         {:ok, result} <-
           Rclex.Nif.tf2_transform!(buffer, message, target, kind) |> native_result(opts) do
      {:ok, restore_structs(message, result)}
    end
  end

  defp geometry_kind(message) when is_map(message) do
    case Enum.filter(
           [:point, :vector, :quaternion, :pose, :transform],
           &Map.has_key?(message, &1)
         ) do
      [kind] -> {:ok, kind}
      _ -> {:error, :unsupported_geometry_type}
    end
  end

  defp geometry_kind(_), do: {:error, :unsupported_geometry_type}

  defp restore_structs(template, result) when is_map(template) and is_map(result) do
    fields =
      Map.new(result, fn {field, value} ->
        {field, restore_structs(Map.get(template, field), value)}
      end)

    if is_struct(template), do: struct(template.__struct__, fields), else: fields
  end

  defp restore_structs(_template, result), do: result

  defp reason_to_string(:lookup), do: "lookup failed"
  defp reason_to_string(:connectivity), do: "frame connectivity failed"
  defp reason_to_string(:extrapolation_past), do: "extrapolation into the past"
  defp reason_to_string(:extrapolation_future), do: "extrapolation into the future"
  defp reason_to_string(:timeout), do: "timeout"
  defp reason_to_string({_kind, message}), do: message
  defp reason_to_string(reason), do: to_string(reason)

  defp validate_frame_ids(target_frame, source_frame) do
    cond do
      not is_binary(target_frame) or String.trim(target_frame) == "" ->
        {:error, :invalid_target_frame}

      not is_binary(source_frame) or String.trim(source_frame) == "" ->
        {:error, :invalid_source_frame}

      true ->
        :ok
    end
  end

  defp extract_edge(transform_stamped) do
    map = to_map(transform_stamped)

    target_frame =
      map
      |> get_in_any([:header, :frame_id])
      |> blank_to_nil()

    source_frame =
      map
      |> get_in_any([:child_frame_id])
      |> blank_to_nil()

    case {target_frame, source_frame} do
      {t, s} when is_binary(t) and is_binary(s) -> {:ok, {t, s}}
      _ -> {:error, :invalid_transform_stamped}
    end
  end

  defp extract_stamp_ns(transform_stamped) do
    map = to_map(transform_stamped)

    sec =
      get_in_any(map, [:header, :stamp, :sec]) || get_in_any(map, [:header, :stamp, :secs]) || 0

    nanosec =
      get_in_any(map, [:header, :stamp, :nanosec]) || get_in_any(map, [:header, :stamp, :nsec]) ||
        0

    if valid_stamp?(sec, nanosec) do
      {:ok, sec * 1_000_000_000 + nanosec}
    else
      {:error, :invalid_stamp}
    end
  end

  defp valid_stamp?(sec, nanosec) do
    is_integer(sec) and sec >= 0 and sec <= 2_147_483_647 and
      is_integer(nanosec) and nanosec >= 0 and nanosec < 1_000_000_000
  end

  defp to_map(%_{} = struct), do: Map.from_struct(struct)
  defp to_map(map) when is_map(map), do: map

  defp get_in_any(map, [key]), do: get_key(map, key)

  defp get_in_any(map, [key | rest]) do
    case get_key(map, key) do
      nil -> nil
      value when is_map(value) -> get_in_any(to_map(value), rest)
      _ -> nil
    end
  end

  defp get_key(map, key) when is_map(map) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end

  defp blank_to_nil(value) when is_binary(value) do
    if String.trim(value) == "", do: nil, else: value
  end

  defp blank_to_nil(_), do: nil

  defp key(buffer_name, name, opts) do
    namespace = Keyword.get(opts, :namespace, "/")
    {to_string(buffer_name), name, if(namespace == "", do: "/", else: namespace)}
  end

  defp deadline_ms(timeout_sec) do
    System.monotonic_time(:millisecond) + max(0, trunc(timeout_sec * 1_000))
  end

  defp wait_until(deadline, query, last_reason \\ nil) do
    case query.() do
      {:retry, reason}
      when reason in [:buffer_not_found, :invalid_target_frame, :invalid_source_frame] ->
        {:error, reason}

      {:retry, {kind, _message} = reason}
      when kind in [:buffer_not_found, :invalid_argument, :native_error] ->
        {:error, reason}

      {:retry, reason} ->
        if System.monotonic_time(:millisecond) >= deadline do
          {:error, if(last_reason, do: :timeout, else: reason)}
        else
          Process.sleep(@poll_ms)
          wait_until(deadline, query, reason)
        end

      result ->
        result
    end
  end

  defp fetch_buffer(buffer_key) do
    case :ets.lookup(@table, buffer_key) do
      [{^buffer_key, buffer}] -> {:ok, buffer}
      [] -> {:error, :buffer_not_found}
    end
  end

  defp ensure_table!, do: ensure_table!(@table)

  defp ensure_table!(table) do
    if :ets.whereis(table) == :undefined do
      GenServer.call(__MODULE__, :ensure_table)
    end
  end

  defp tf_message_type_module(opts) do
    Keyword.get(
      opts,
      :tf_message_type_module,
      Module.concat([Rclex, Pkgs, Tf2Msgs, Msg, TFMessage])
    )
  end

  defp ensure_tf_message_type_available(opts) do
    mod = tf_message_type_module(opts)

    if Code.ensure_loaded?(mod) do
      :ok
    else
      {:error,
       {:tf_message_type_not_generated,
        "Generate tf2_msgs/msg/TFMessage and ensure module #{inspect(mod)} exists"}}
    end
  end

  defp ensure_subscription(topic_kind, buffer_name, name, authority, opts, state) do
    listener_key = {key(buffer_name, name, opts), topic_kind}

    if Map.has_key?(state.listeners, listener_key) do
      {:ok, state}
    else
      tf_message_type = tf_message_type_module(opts)
      topic = topic_name(topic_kind)

      callback = fn msg ->
        ingest_tf_message(msg, topic_kind == :tf_static, buffer_name, name, opts, authority)
      end

      transport = %{
        message_type: tf_message_type,
        topic: topic,
        name: name,
        opts: topic_options(topic_kind, :listener, opts)
      }

      result = Cleanup.start_transport(:listener, transport, callback)
      record_transport_start(result, :listeners, listener_key, transport, state)
    end
  end

  defp ensure_publisher(topic_kind, name, opts, state) do
    namespace = Keyword.get(opts, :namespace, "/")
    broadcaster_key = {name, namespace, topic_kind}

    if Map.has_key?(state.broadcasters, broadcaster_key) do
      {:ok, state}
    else
      tf_message_type = tf_message_type_module(opts)
      topic = topic_name(topic_kind)

      transport = %{
        message_type: tf_message_type,
        topic: topic,
        name: name,
        opts: topic_options(topic_kind, :broadcaster, opts)
      }

      result = Cleanup.start_transport(:broadcaster, transport)
      record_transport_start(result, :broadcasters, broadcaster_key, transport, state)
    end
  end

  defp record_transport_start(result, collection, transport_key, transport, state)
       when result in [:ok, {:error, :already_started}] do
    {:ok, Map.update!(state, collection, &Map.put(&1, transport_key, transport))}
  end

  defp record_transport_start(
         {:error, _} = error,
         _collection,
         _transport_key,
         _transport,
         state
       ),
       do: {error, state}

  defp topic_name(:tf), do: "/tf"
  defp topic_name(:tf_static), do: "/tf_static"

  defp topic_options(topic_kind, role, opts) do
    default =
      case {topic_kind, role} do
        {:tf_static, :broadcaster} -> %Rclex.QoS{depth: 1, durability: :transient_local}
        {:tf_static, :listener} -> %Rclex.QoS{depth: 100, durability: :transient_local}
        {:tf, _} -> %Rclex.QoS{depth: 100}
      end

    qos_key = if topic_kind == :tf_static, do: :tf_static_qos, else: :tf_qos
    Keyword.put(opts, :qos, Keyword.get(opts, qos_key, Keyword.get(opts, :qos, default)))
  end

  defp publish_tf_message(transform_stamped_or_list, topic, name, opts) do
    ensure_table!()

    with :ok <- ensure_tf_message_type_available(opts) do
      tf_message_type = tf_message_type_module(opts)
      tf_message = build_tf_message(tf_message_type, transform_stamped_or_list)
      Rclex.publish(tf_message, topic, name, opts)
    end
  end

  defp build_tf_message(tf_message_type, transform_stamped_or_list) do
    transforms =
      case transform_stamped_or_list do
        list when is_list(list) -> list
        single -> [single]
      end

    struct(tf_message_type, %{transforms: transforms})
  end

  defp ingest_tf_message(msg, is_static, buffer_name, name, opts, authority) do
    transforms = Map.get(to_map(msg), :transforms) || Map.get(to_map(msg), "transforms") || []

    Enum.each(transforms, fn transform_stamped ->
      if is_static do
        _ = set_transform_static(buffer_name, transform_stamped, authority, name, opts)
      else
        _ = set_transform(buffer_name, transform_stamped, authority, name, opts)
      end
    end)
  end

  defp normalize_transform(transform_stamped) do
    map = to_map(transform_stamped)

    transform = get_in_any(map, [:transform]) || map

    with {:ok, translation} <- normalize_translation(get_in_any(transform, [:translation])),
         {:ok, rotation} <- normalize_rotation(get_in_any(transform, [:rotation])) do
      {:ok, %{translation: translation, rotation: rotation}}
    else
      _ -> {:error, :invalid_transform_stamped}
    end
  end

  defp normalize_translation(%{} = translation) do
    x = get_in_any(translation, [:x])
    y = get_in_any(translation, [:y])
    z = get_in_any(translation, [:z])

    if is_number(x) and is_number(y) and is_number(z) do
      {:ok, %{x: x * 1.0, y: y * 1.0, z: z * 1.0}}
    else
      {:error, :invalid_translation}
    end
  end

  defp normalize_translation(_), do: {:error, :invalid_translation}

  defp normalize_rotation(%{} = rotation) do
    w = get_in_any(rotation, [:w])
    x = get_in_any(rotation, [:x])
    y = get_in_any(rotation, [:y])
    z = get_in_any(rotation, [:z])

    if is_number(w) and is_number(x) and is_number(y) and is_number(z) do
      {:ok, %{w: w * 1.0, x: x * 1.0, y: y * 1.0, z: z * 1.0}}
    else
      {:error, :invalid_rotation}
    end
  end

  defp normalize_rotation(_), do: {:error, :invalid_rotation}

  defp validate_quaternion(q) do
    if q.w == 0 and q.x == 0 and q.y == 0 and q.z == 0,
      do: {:error, :invalid_quaternion},
      else: :ok
  end
end
