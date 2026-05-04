defmodule Rclex.Tf2 do
  @moduledoc false

  @table :rclex_tf2_buffers
  @io_table :rclex_tf2_io
  @poll_ms 5
  @default_cache_time_sec 10.0

  @type buffer_name :: String.t() | atom()
  @type opts :: keyword()

  @spec buffer_new(buffer_name(), String.t(), opts()) :: :ok | {:error, term()}
  def buffer_new(buffer_name, name, opts \\ []) do
    ensure_table!()
    ensure_io_table!()
    key = key(buffer_name, name, opts)

    cache_time_sec = Keyword.get(opts, :cache_time_sec, @default_cache_time_sec)
    cache_time_ns = max(0, trunc(cache_time_sec * 1_000_000_000))

    case :ets.lookup(@table, key) do
      [] ->
        true =
          :ets.insert(@table, {
            key,
            %{dynamic: %{}, static: %{}, cache_time_ns: cache_time_ns}
          })

        :ok

      _ ->
        {:error, :buffer_already_exists}
    end
  end

  @spec buffer_destroy(buffer_name(), String.t(), opts()) :: :ok | {:error, term()}
  def buffer_destroy(buffer_name, name, opts \\ []) do
    ensure_table!()
    ensure_io_table!()
    key = key(buffer_name, name, opts)

    stop_listener(buffer_name, name, opts)
    stop_broadcaster(name, opts)

    case :ets.lookup(@table, key) do
      [] ->
        {:error, :buffer_not_found}

      _ ->
        true = :ets.delete(@table, key)
        :ok
    end
  end

  @spec clear(buffer_name(), String.t(), opts()) :: :ok | {:error, term()}
  def clear(buffer_name, name, opts \\ []) do
    ensure_table!()
    ensure_io_table!()
    key = key(buffer_name, name, opts)

    with {:ok, buffer} <- fetch_buffer(key) do
      true = :ets.insert(@table, {key, %{buffer | dynamic: %{}, static: %{}}})
      :ok
    end
  end

  @spec all_frames_as_yaml(buffer_name(), String.t(), opts()) ::
          {:ok, String.t()} | {:error, term()}
  def all_frames_as_yaml(buffer_name, name, opts \\ []) do
    ensure_table!()
    ensure_io_table!()
    key = key(buffer_name, name, opts)

    with {:ok, buffer} <- fetch_buffer(key) do
      {:ok, all_frames_yaml(buffer)}
    end
  end

  @spec get_latest_common_time(buffer_name(), String.t(), String.t(), String.t(), opts()) ::
          {:ok, integer()} | {:error, term()}
  def get_latest_common_time(buffer_name, target_frame, source_frame, name, opts \\ []) do
    ensure_table!()
    ensure_io_table!()
    key = key(buffer_name, name, opts)

    with {:ok, buffer} <- fetch_buffer(key),
         :ok <- validate_frame_ids(target_frame, source_frame),
         :ok <- ensure_known_frames(buffer, target_frame, source_frame) do
      latest_common_time_ns(buffer, target_frame, source_frame)
    end
  end

  @spec set_transform(buffer_name(), map() | struct(), String.t(), String.t(), opts()) ::
          :ok | {:error, term()}
  def set_transform(buffer_name, transform_stamped, authority \\ "", name, opts \\ []) do
    ensure_table!()
    ensure_io_table!()
    key = key(buffer_name, name, opts)

    with {:ok, buffer} <- fetch_buffer(key),
         {:ok, edge} <- extract_edge(transform_stamped),
         {:ok, stamp_ns} <- extract_stamp_ns(transform_stamped),
         {:ok, normalized_tf} <- normalize_transform(transform_stamped),
         :ok <- validate_quaternion(normalized_tf.rotation) do
      sample = %{stamp_ns: stamp_ns, transform: normalized_tf, authority: authority}
      samples = Map.get(buffer.dynamic, edge, [])
      updated_samples = samples |> insert_sample(sample) |> trim_samples(buffer.cache_time_ns)

      updated_dynamic = Map.put(buffer.dynamic, edge, updated_samples)
      true = :ets.insert(@table, {key, %{buffer | dynamic: updated_dynamic}})
      :ok
    end
  end

  @spec set_transform_static(buffer_name(), map() | struct(), String.t(), String.t(), opts()) ::
          :ok | {:error, term()}
  def set_transform_static(buffer_name, transform_stamped, authority \\ "", name, opts \\ []) do
    ensure_table!()
    ensure_io_table!()
    key = key(buffer_name, name, opts)

    with {:ok, buffer} <- fetch_buffer(key),
         {:ok, edge} <- extract_edge(transform_stamped),
         {:ok, normalized_tf} <- normalize_transform(transform_stamped),
         :ok <- validate_quaternion(normalized_tf.rotation) do
      updated_static =
        Map.put(buffer.static, edge, %{transform: normalized_tf, authority: authority})

      true = :ets.insert(@table, {key, %{buffer | static: updated_static}})
      :ok
    end
  end

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
      ) do
    ensure_table!()
    ensure_io_table!()
    key = key(buffer_name, name, opts)
    return_debug_tuple = Keyword.get(opts, :return_debug_tuple, false)

    with {:ok, _} <- fetch_buffer(key) do
      deadline = deadline_ms(timeout_sec)

      result =
        wait_until(deadline, :lookup, fn ->
          probe_can_transform(key, target_frame, source_frame, time_ns)
        end)

      can_transform_result(result, return_debug_tuple)
    end
  end

  defp probe_can_transform(key, target_frame, source_frame, time_ns) do
    case lookup_internal(key, target_frame, source_frame, time_ns) do
      {:ok, _} -> {:ok, true}
      {:error, reason} -> {:retry, reason}
    end
  end

  defp can_transform_result({:ok, true}, true), do: {true, ""}
  defp can_transform_result({:ok, true}, false), do: true
  defp can_transform_result({:error, reason}, true), do: {false, reason_to_string(reason)}
  defp can_transform_result({:error, _reason}, false), do: false

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
      ) do
    ensure_table!()
    ensure_io_table!()
    key = key(buffer_name, name, opts)
    deadline = deadline_ms(timeout_sec)

    wait_until(deadline, :lookup, fn ->
      case lookup_internal(key, target_frame, source_frame, time_ns) do
        {:ok, transform} -> {:ok, transform}
        {:error, reason} -> {:retry, reason}
      end
    end)
  end

  @spec start_listener(buffer_name(), String.t(), opts()) :: :ok | {:error, term()}
  def start_listener(buffer_name, name, opts \\ []) do
    ensure_table!()
    ensure_io_table!()

    namespace = Keyword.get(opts, :namespace, "/")
    authority = Keyword.get(opts, :authority, "tf_listener")

    with :ok <- ensure_tf_message_type_available(opts),
         {:ok, _} <- fetch_buffer(key(buffer_name, name, opts)),
         :ok <- ensure_subscription(:tf, buffer_name, name, namespace, authority, opts) do
      ensure_subscription(:tf_static, buffer_name, name, namespace, authority, opts)
    end
  end

  @spec stop_listener(buffer_name(), String.t(), opts()) :: :ok | {:error, term()}
  def stop_listener(buffer_name, name, opts \\ []) do
    ensure_table!()
    ensure_io_table!()

    with :ok <- ensure_tf_message_type_available(opts) do
      tf_message_type = tf_message_type_module(opts)

      _ = safe_rclex_call(fn -> Rclex.stop_subscription(tf_message_type, "/tf", name, opts) end)

      _ =
        safe_rclex_call(fn ->
          Rclex.stop_subscription(tf_message_type, "/tf_static", name, opts)
        end)

      namespace = Keyword.get(opts, :namespace, "/")
      _ = :ets.delete(@io_table, {:listener, buffer_name, name, namespace, :tf})
      _ = :ets.delete(@io_table, {:listener, buffer_name, name, namespace, :tf_static})

      :ok
    end
  end

  @spec start_broadcaster(String.t(), opts()) :: :ok | {:error, term()}
  def start_broadcaster(name, opts \\ []) do
    ensure_table!()
    ensure_io_table!()

    with :ok <- ensure_tf_message_type_available(opts),
         :ok <- ensure_publisher(:tf, name, opts) do
      ensure_publisher(:tf_static, name, opts)
    end
  end

  @spec stop_broadcaster(String.t(), opts()) :: :ok | {:error, term()}
  def stop_broadcaster(name, opts \\ []) do
    ensure_table!()
    ensure_io_table!()

    with :ok <- ensure_tf_message_type_available(opts) do
      tf_message_type = tf_message_type_module(opts)
      _ = safe_rclex_call(fn -> Rclex.stop_publisher(tf_message_type, "/tf", name, opts) end)

      _ =
        safe_rclex_call(fn -> Rclex.stop_publisher(tf_message_type, "/tf_static", name, opts) end)

      namespace = Keyword.get(opts, :namespace, "/")
      _ = :ets.delete(@io_table, {:broadcaster, name, namespace, :tf})
      _ = :ets.delete(@io_table, {:broadcaster, name, namespace, :tf_static})

      :ok
    end
  end

  defp safe_rclex_call(fun) do
    try do
      fun.()
    catch
      :exit, _ -> :ok
    end
  end

  @spec broadcast_dynamic([map() | struct()] | map() | struct(), String.t(), opts()) ::
          :ok | {:error, term()}
  def broadcast_dynamic(transform_stamped_or_list, name, opts \\ []) do
    publish_tf_message(transform_stamped_or_list, "/tf", name, opts)
  end

  @spec broadcast_static([map() | struct()] | map() | struct(), String.t(), opts()) ::
          :ok | {:error, term()}
  def broadcast_static(transform_stamped_or_list, name, opts \\ []) do
    publish_tf_message(transform_stamped_or_list, "/tf_static", name, opts)
  end

  defp lookup_internal(key, target_frame, source_frame, time_ns) do
    with {:ok, buffer} <- fetch_buffer(key),
         :ok <- validate_frame_ids(target_frame, source_frame),
         :ok <- ensure_known_frames(buffer, target_frame, source_frame),
         {:ok, query_time_ns} <- resolve_query_time(buffer, target_frame, source_frame, time_ns),
         {:ok, transform} <-
           resolve_path_transform(buffer, target_frame, source_frame, query_time_ns) do
      {:ok,
       %{
         header: %{frame_id: target_frame, stamp: ns_to_stamp(query_time_ns)},
         child_frame_id: source_frame,
         transform: transform
       }}
    end
  end

  defp resolve_query_time(_buffer, _target_frame, _source_frame, time_ns) when time_ns > 0,
    do: {:ok, time_ns}

  defp resolve_query_time(buffer, target_frame, source_frame, _time_ns) do
    latest_common_time_ns(buffer, target_frame, source_frame)
  end

  defp latest_common_time_ns(buffer, target_frame, source_frame) do
    case resolve_path_transform(buffer, target_frame, source_frame, :latest, true) do
      {:ok, _transform, latest_stamp_ns} -> {:ok, latest_stamp_ns}
      {:error, reason} -> {:error, reason}
    end
  end

  defp resolve_path_transform(
         buffer,
         target_frame,
         source_frame,
         query_time_ns,
         only_time \\ false
       ) do
    start = {target_frame, identity_transform(), query_time_ns}

    bfs_result =
      do_resolve_path_transform(
        [start],
        MapSet.new([target_frame]),
        buffer,
        source_frame,
        query_time_ns,
        nil
      )

    case bfs_result do
      {:ok, transform, latest_stamp_ns} ->
        if only_time, do: {:ok, transform, latest_stamp_ns}, else: {:ok, transform}

      {:error, reason} ->
        if path_exists?(buffer, target_frame, source_frame) and
             reason not in [:lookup, :connectivity] do
          {:error, reason}
        else
          {:error, :connectivity}
        end
    end
  end

  defp do_resolve_path_transform([], _visited, _buffer, _source_frame, _query_time_ns, nil),
    do: {:error, :connectivity}

  defp do_resolve_path_transform([], _visited, _buffer, _source_frame, _query_time_ns, reason),
    do: {:error, reason}

  defp do_resolve_path_transform(
         [{current_frame, acc_transform, min_stamp_ns} | rest],
         visited,
         buffer,
         source_frame,
         query_time_ns,
         best_reason
       ) do
    if current_frame == source_frame do
      {:ok, acc_transform, min_stamp_ns}
    else
      {rest2, visited2, reason2} =
        Enum.reduce(
          neighbors(buffer, current_frame, query_time_ns),
          {rest, visited, best_reason},
          &fold_resolve_neighbor(&1, &2, acc_transform, min_stamp_ns)
        )

      do_resolve_path_transform(rest2, visited2, buffer, source_frame, query_time_ns, reason2)
    end
  end

  defp fold_resolve_neighbor(
         {:ok, next_frame, edge_transform, edge_stamp_ns},
         {queue, seen, reason},
         acc_transform,
         min_stamp_ns
       ) do
    if MapSet.member?(seen, next_frame) do
      {queue, seen, reason}
    else
      composed = compose_transform(acc_transform, edge_transform)
      new_min_stamp = min_stamp(min_stamp_ns, edge_stamp_ns)
      {queue ++ [{next_frame, composed, new_min_stamp}], MapSet.put(seen, next_frame), reason}
    end
  end

  defp fold_resolve_neighbor(
         {:error, edge_reason},
         {queue, seen, reason},
         _acc_transform,
         _min_stamp_ns
       ) do
    {queue, seen, prefer_reason(reason, edge_reason)}
  end

  defp neighbors(buffer, frame, query_time_ns) do
    static_edges = Enum.flat_map(buffer.static, &static_edge_for_frame(&1, frame))

    dynamic_edges =
      Enum.flat_map(buffer.dynamic, &dynamic_edge_for_frame(&1, frame, query_time_ns))

    static_edges ++ dynamic_edges
  end

  defp static_edge_for_frame({{target, source}, %{transform: transform}}, frame) do
    cond do
      target == frame -> [{:ok, source, transform, :infinite}]
      source == frame -> [{:ok, target, invert_transform(transform), :infinite}]
      true -> []
    end
  end

  defp static_edge_for_frame(_, _), do: []

  defp dynamic_edge_for_frame({{target, source}, samples}, frame, query_time_ns) do
    cond do
      target == frame -> dynamic_edge_sample(samples, source, query_time_ns, :forward)
      source == frame -> dynamic_edge_sample(samples, target, query_time_ns, :inverse)
      true -> []
    end
  end

  defp dynamic_edge_for_frame(_, _, _), do: []

  defp dynamic_edge_sample(samples, other_frame, query_time_ns, direction) do
    case transform_from_samples(samples, query_time_ns) do
      {:ok, transform, stamp_ns} ->
        edge_transform =
          case direction do
            :forward -> transform
            :inverse -> invert_transform(transform)
          end

        [{:ok, other_frame, edge_transform, stamp_ns}]

      {:error, reason} ->
        [{:error, reason}]
    end
  end

  defp transform_from_samples([], _query_time_ns), do: {:error, :lookup}

  defp transform_from_samples(samples, :latest) do
    case List.last(samples) do
      nil -> {:error, :lookup}
      sample -> {:ok, sample.transform, sample.stamp_ns}
    end
  end

  defp transform_from_samples([sample], query_time_ns) do
    cond do
      query_time_ns == sample.stamp_ns -> {:ok, sample.transform, sample.stamp_ns}
      query_time_ns < sample.stamp_ns -> {:error, :extrapolation_past}
      query_time_ns > sample.stamp_ns -> {:error, :extrapolation_future}
      true -> {:ok, sample.transform, sample.stamp_ns}
    end
  end

  defp transform_from_samples(samples, query_time_ns) do
    first = hd(samples)
    last = List.last(samples)

    cond do
      query_time_ns < first.stamp_ns ->
        {:error, :extrapolation_past}

      query_time_ns > last.stamp_ns ->
        {:error, :extrapolation_future}

      true ->
        interpolate_samples(samples, query_time_ns)
    end
  end

  defp interpolate_samples(samples, query_time_ns) do
    case Enum.find(samples, fn sample -> sample.stamp_ns == query_time_ns end) do
      nil ->
        pair =
          samples
          |> Enum.chunk_every(2, 1, :discard)
          |> Enum.find(fn [a, b] ->
            a.stamp_ns <= query_time_ns and query_time_ns <= b.stamp_ns
          end)

        case pair do
          [a, b] when a.stamp_ns == b.stamp_ns -> {:ok, a.transform, a.stamp_ns}
          [a, b] -> {:ok, interpolate_transform(a, b, query_time_ns), query_time_ns}
          _ -> {:error, :lookup}
        end

      sample ->
        {:ok, sample.transform, sample.stamp_ns}
    end
  end

  defp interpolate_transform(a, b, query_time_ns) do
    ratio = (query_time_ns - a.stamp_ns) / (b.stamp_ns - a.stamp_ns)

    %{
      translation: %{
        x: lerp(a.transform.translation.x, b.transform.translation.x, ratio),
        y: lerp(a.transform.translation.y, b.transform.translation.y, ratio),
        z: lerp(a.transform.translation.z, b.transform.translation.z, ratio)
      },
      rotation: slerp(a.transform.rotation, b.transform.rotation, ratio)
    }
  end

  defp lerp(a, b, r), do: a + (b - a) * r

  defp slerp(q1, q2, ratio) do
    q1n = normalize_quaternion(q1)
    q2n = normalize_quaternion(q2)

    dot = dot_quaternion(q1n, q2n)

    {qa, qb, d} =
      if dot < 0.0 do
        {q1n, negate_quaternion(q2n), -dot}
      else
        {q1n, q2n, dot}
      end

    if d > 0.9995 do
      normalize_quaternion(%{
        w: lerp(qa.w, qb.w, ratio),
        x: lerp(qa.x, qb.x, ratio),
        y: lerp(qa.y, qb.y, ratio),
        z: lerp(qa.z, qb.z, ratio)
      })
    else
      theta_0 = :math.acos(d)
      theta = theta_0 * ratio
      sin_theta = :math.sin(theta)
      sin_theta_0 = :math.sin(theta_0)
      s0 = :math.cos(theta) - d * sin_theta / sin_theta_0
      s1 = sin_theta / sin_theta_0

      normalize_quaternion(%{
        w: s0 * qa.w + s1 * qb.w,
        x: s0 * qa.x + s1 * qb.x,
        y: s0 * qa.y + s1 * qb.y,
        z: s0 * qa.z + s1 * qb.z
      })
    end
  end

  defp dot_quaternion(a, b), do: a.w * b.w + a.x * b.x + a.y * b.y + a.z * b.z

  defp negate_quaternion(q), do: %{w: -q.w, x: -q.x, y: -q.y, z: -q.z}

  defp min_stamp(:infinite, s), do: s
  defp min_stamp(s, :infinite), do: s
  defp min_stamp(a, b), do: min(a, b)

  defp prefer_reason(nil, reason), do: reason

  defp prefer_reason(current, candidate) do
    ranking = %{
      extrapolation_future: 4,
      extrapolation_past: 4,
      lookup: 3,
      connectivity: 2,
      timeout: 1
    }

    if Map.get(ranking, candidate, 0) >= Map.get(ranking, current, 0),
      do: candidate,
      else: current
  end

  defp reason_to_string(:lookup), do: "lookup failed"
  defp reason_to_string(:connectivity), do: "frame connectivity failed"
  defp reason_to_string(:extrapolation_past), do: "extrapolation into the past"
  defp reason_to_string(:extrapolation_future), do: "extrapolation into the future"
  defp reason_to_string(:timeout), do: "timeout"
  defp reason_to_string(reason), do: to_string(reason)

  defp path_exists?(buffer, target_frame, source_frame) do
    start = [target_frame]
    do_path_exists?(start, MapSet.new([target_frame]), buffer, source_frame)
  end

  defp do_path_exists?([], _visited, _buffer, _source_frame), do: false

  defp do_path_exists?([current | rest], visited, buffer, source_frame) do
    if current == source_frame do
      true
    else
      nexts = path_neighbor_frames(buffer, current)
      {queue, visited2} = enqueue_unseen(nexts, rest, visited)
      do_path_exists?(queue, visited2, buffer, source_frame)
    end
  end

  defp path_neighbor_frames(buffer, current) do
    Enum.flat_map(all_edges(buffer), fn {target, source} ->
      cond do
        target == current -> [source]
        source == current -> [target]
        true -> []
      end
    end)
  end

  defp enqueue_unseen(nexts, queue, visited) do
    Enum.reduce(nexts, {queue, visited}, fn frame, {q, seen} ->
      if MapSet.member?(seen, frame) do
        {q, seen}
      else
        {q ++ [frame], MapSet.put(seen, frame)}
      end
    end)
  end

  defp all_edges(buffer) do
    (Map.keys(buffer.static) ++ Map.keys(buffer.dynamic))
    |> Enum.uniq()
  end

  defp known_frames(buffer) do
    all_edges(buffer)
    |> Enum.reduce(MapSet.new(), fn {target, source}, acc ->
      acc |> MapSet.put(target) |> MapSet.put(source)
    end)
    |> MapSet.to_list()
  end

  defp all_frames_yaml(buffer) do
    entries = frame_yaml_entries(buffer)

    if map_size(entries) == 0 do
      ""
    else
      entries
      |> Map.keys()
      |> Enum.sort()
      |> Enum.flat_map(fn child ->
        info = Map.fetch!(entries, child)

        [
          "#{child}:",
          "  parent: #{info.parent}",
          "  broadcaster: #{info.broadcaster}",
          "  rate: #{float_to_string(info.rate)}",
          "  most_recent_transform: #{float_to_string(info.most_recent_transform)}",
          "  oldest_transform: #{float_to_string(info.oldest_transform)}",
          "  buffer_length: #{float_to_string(info.buffer_length)}"
        ]
      end)
      |> Enum.join("\n")
    end
  end

  defp frame_yaml_entries(buffer) do
    static_entries =
      Enum.reduce(buffer.static, %{}, fn
        {{parent, child}, %{authority: authority}}, acc ->
          Map.put(acc, child, %{
            parent: parent,
            broadcaster: normalize_broadcaster(authority),
            rate: 0.0,
            most_recent_transform: 0.0,
            oldest_transform: 0.0,
            buffer_length: 0.0,
            stamp_ns: 0
          })

        _, acc ->
          acc
      end)

    Enum.reduce(buffer.dynamic, static_entries, fn
      {{parent, child}, samples}, acc when is_list(samples) and samples != [] ->
        oldest = hd(samples)
        latest = List.last(samples)
        span_ns = max(0, latest.stamp_ns - oldest.stamp_ns)

        rate =
          if span_ns > 0 and length(samples) > 1 do
            (length(samples) - 1) / (span_ns / 1_000_000_000)
          else
            0.0
          end

        info = %{
          parent: parent,
          broadcaster: normalize_broadcaster(latest.authority),
          rate: rate,
          most_recent_transform: latest.stamp_ns / 1_000_000_000,
          oldest_transform: oldest.stamp_ns / 1_000_000_000,
          buffer_length: span_ns / 1_000_000_000,
          stamp_ns: latest.stamp_ns
        }

        case Map.get(acc, child) do
          nil -> Map.put(acc, child, info)
          existing when existing.stamp_ns <= info.stamp_ns -> Map.put(acc, child, info)
          _ -> acc
        end

      _, acc ->
        acc
    end)
  end

  defp normalize_broadcaster(authority) when is_binary(authority) and authority != "",
    do: authority

  defp normalize_broadcaster(_), do: "unknown"

  defp float_to_string(value) when is_float(value) do
    :erlang.float_to_binary(value, decimals: 6)
  end

  defp float_to_string(value) when is_integer(value), do: Integer.to_string(value)

  defp ensure_known_frames(buffer, target_frame, source_frame) do
    frames = known_frames(buffer)

    cond do
      target_frame == source_frame -> :ok
      target_frame in frames and source_frame in frames -> :ok
      true -> {:error, :lookup}
    end
  end

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

    if is_integer(sec) and is_integer(nanosec) and sec >= 0 and nanosec >= 0 do
      {:ok, sec * 1_000_000_000 + nanosec}
    else
      {:error, :invalid_stamp}
    end
  end

  defp ns_to_stamp(ns) when is_integer(ns) and ns >= 0 do
    %{sec: div(ns, 1_000_000_000), nanosec: rem(ns, 1_000_000_000)}
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

  defp blank_to_nil(v) when is_binary(v) do
    if String.trim(v) == "", do: nil, else: v
  end

  defp blank_to_nil(_), do: nil

  defp key(buffer_name, name, opts) do
    namespace = opts |> Keyword.get(:namespace, "/") |> normalize_namespace()
    {to_string(buffer_name), name, namespace}
  end

  defp normalize_namespace(ns) when is_binary(ns) do
    if ns == "", do: "/", else: ns
  end

  defp deadline_ms(timeout_sec) when is_float(timeout_sec) or is_integer(timeout_sec) do
    now = System.monotonic_time(:millisecond)
    add = max(0, trunc(timeout_sec * 1_000))
    now + add
  end

  defp wait_until(deadline_ms, mode, fun, last_reason \\ nil) do
    case fun.() do
      {:retry, reason} ->
        if System.monotonic_time(:millisecond) >= deadline_ms do
          {:error, if(last_reason, do: :timeout, else: reason)}
        else
          Process.sleep(@poll_ms)
          wait_until(deadline_ms, mode, fun, reason)
        end

      result ->
        result
    end
  end

  defp fetch_buffer(key) do
    case :ets.lookup(@table, key) do
      [{^key, buffer}] -> {:ok, buffer}
      [] -> {:error, :buffer_not_found}
    end
  end

  defp ensure_table! do
    case :ets.whereis(@table) do
      :undefined ->
        try do
          :ets.new(@table, [
            :named_table,
            :public,
            :set,
            read_concurrency: true,
            write_concurrency: true
          ])
        rescue
          _ -> :ok
        else
          _ -> :ok
        end

      _ ->
        :ok
    end
  end

  defp ensure_io_table! do
    case :ets.whereis(@io_table) do
      :undefined ->
        try do
          :ets.new(@io_table, [
            :named_table,
            :public,
            :set,
            read_concurrency: true,
            write_concurrency: true
          ])
        rescue
          _ -> :ok
        else
          _ -> :ok
        end

      _ ->
        :ok
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

  defp ensure_subscription(topic_kind, buffer_name, name, namespace, authority, opts) do
    io_key = {:listener, buffer_name, name, namespace, topic_kind}

    case :ets.lookup(@io_table, io_key) do
      [] ->
        tf_message_type = tf_message_type_module(opts)
        topic = topic_name(topic_kind)

        callback = fn msg ->
          ingest_tf_message(msg, topic_kind == :tf_static, buffer_name, name, opts, authority)
        end

        case Rclex.start_subscription(callback, tf_message_type, topic, name, opts) do
          :ok ->
            true = :ets.insert(@io_table, {io_key, true})
            :ok

          {:error, :already_started} ->
            true = :ets.insert(@io_table, {io_key, true})
            :ok

          {:error, reason} ->
            {:error, reason}
        end

      _ ->
        :ok
    end
  end

  defp ensure_publisher(topic_kind, name, opts) do
    namespace = Keyword.get(opts, :namespace, "/")
    io_key = {:broadcaster, name, namespace, topic_kind}

    case :ets.lookup(@io_table, io_key) do
      [] ->
        tf_message_type = tf_message_type_module(opts)
        topic = topic_name(topic_kind)

        case Rclex.start_publisher(tf_message_type, topic, name, opts) do
          :ok ->
            true = :ets.insert(@io_table, {io_key, true})
            :ok

          {:error, :already_started} ->
            true = :ets.insert(@io_table, {io_key, true})
            :ok

          {:error, reason} ->
            {:error, reason}
        end

      _ ->
        :ok
    end
  end

  defp topic_name(:tf), do: "/tf"
  defp topic_name(:tf_static), do: "/tf_static"

  defp publish_tf_message(transform_stamped_or_list, topic, name, opts) do
    ensure_table!()
    ensure_io_table!()

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
    norm = :math.sqrt(q.w * q.w + q.x * q.x + q.y * q.y + q.z * q.z)
    if norm > 0.0, do: :ok, else: {:error, :invalid_quaternion}
  end

  defp insert_sample(samples, sample) do
    (samples ++ [sample])
    |> Enum.sort_by(& &1.stamp_ns)
    |> dedupe_samples()
  end

  defp dedupe_samples(samples) do
    samples
    |> Enum.reduce(%{}, fn sample, acc -> Map.put(acc, sample.stamp_ns, sample) end)
    |> Map.values()
    |> Enum.sort_by(& &1.stamp_ns)
  end

  defp trim_samples(samples, cache_time_ns) when cache_time_ns == 0,
    do: [List.last(samples)] |> Enum.reject(&is_nil/1)

  defp trim_samples(samples, cache_time_ns) do
    case List.last(samples) do
      nil ->
        []

      latest ->
        Enum.filter(samples, fn sample -> latest.stamp_ns - sample.stamp_ns <= cache_time_ns end)
    end
  end

  defp identity_transform do
    %{
      translation: %{x: 0.0, y: 0.0, z: 0.0},
      rotation: %{w: 1.0, x: 0.0, y: 0.0, z: 0.0}
    }
  end

  defp compose_transform(left, right) do
    left_t = left.translation
    left_r = normalize_quaternion(left.rotation)
    right_t = right.translation
    right_r = normalize_quaternion(right.rotation)

    rotated_right_t = rotate_vector(left_r, right_t)

    %{
      translation: add_vec(left_t, rotated_right_t),
      rotation: normalize_quaternion(quat_mul(left_r, right_r))
    }
  end

  defp invert_transform(transform) do
    rotation_inv = quat_conjugate(normalize_quaternion(transform.rotation))
    translation_inv = scalar_mul(rotate_vector(rotation_inv, transform.translation), -1.0)

    %{translation: translation_inv, rotation: rotation_inv}
  end

  defp rotate_vector(q, v) do
    q_vec = %{w: 0.0, x: v.x, y: v.y, z: v.z}
    rotated = quat_mul(quat_mul(q, q_vec), quat_conjugate(q))
    %{x: rotated.x, y: rotated.y, z: rotated.z}
  end

  defp quat_mul(a, b) do
    %{
      w: a.w * b.w - a.x * b.x - a.y * b.y - a.z * b.z,
      x: a.w * b.x + a.x * b.w + a.y * b.z - a.z * b.y,
      y: a.w * b.y - a.x * b.z + a.y * b.w + a.z * b.x,
      z: a.w * b.z + a.x * b.y - a.y * b.x + a.z * b.w
    }
  end

  defp quat_conjugate(q), do: %{w: q.w, x: -q.x, y: -q.y, z: -q.z}

  defp normalize_quaternion(q) do
    norm = :math.sqrt(q.w * q.w + q.x * q.x + q.y * q.y + q.z * q.z)

    if norm == 0.0 do
      %{w: 1.0, x: 0.0, y: 0.0, z: 0.0}
    else
      %{w: q.w / norm, x: q.x / norm, y: q.y / norm, z: q.z / norm}
    end
  end

  defp add_vec(a, b), do: %{x: a.x + b.x, y: a.y + b.y, z: a.z + b.z}
  defp scalar_mul(v, k), do: %{x: v.x * k, y: v.y * k, z: v.z * k}
end
