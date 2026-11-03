defmodule Rclex.Tf2Test do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Rclex.Pkgs.BuiltinInterfaces.Msg.Time
  alias Rclex.Pkgs.GeometryMsgs.Msg.{Quaternion, Transform, TransformStamped, Vector3}
  alias Rclex.Pkgs.StdMsgs.Msg.Header

  @table :rclex_tf2_buffers

  setup do
    :ok = Application.ensure_started(:rclex)

    if :ets.whereis(@table) != :undefined do
      Enum.each(:ets.tab2list(@table), fn {{buffer_name, name, namespace}, _resource} ->
        Rclex.Tf2.buffer_destroy(buffer_name, name, namespace: namespace)
      end)
    end

    :ok
  end

  defp stamped_transform(
         parent,
         child,
         sec,
         translation,
         rotation \\ %{w: 1.0, x: 0.0, y: 0.0, z: 0.0}
       ) do
    %{
      header: %{frame_id: parent, stamp: %{sec: sec, nanosec: 0}},
      child_frame_id: child,
      transform: %{translation: translation, rotation: rotation}
    }
  end

  describe "buffer lifecycle" do
    test "abrupt restart invalidates native handles before accepting new buffers" do
      clock = start_supervised!({Rclex.Clock, name: :tf2_crash_clock, clock_type: :ros_time})
      assert :ok = Rclex.Tf2.buffer_new("crash", "node", clock: clock)
      assert [{_, resource}] = :ets.lookup(@table, {"crash", "node", "/"})

      assert {:ok, request} =
               Rclex.Tf2.lookup_transform_async("crash", "map", "missing", 0, 10.0, "node")

      owner = Process.whereis(Rclex.Tf2)
      monitor = Process.monitor(owner)

      capture_log(fn ->
        Process.exit(owner, :kill)
        assert_receive {:DOWN, ^monitor, :process, ^owner, :killed}
        new_owner = await_tf2_restart(owner)
        assert :ok = GenServer.call(new_owner, :ensure_table)
        assert {:error, {:buffer_not_found, _}} = Rclex.Nif.tf2_clear!(resource)
        assert :ros_time = Rclex.Clock.clock_type(clock)
        assert {:monitors, []} = Process.info(clock, :monitors)
        assert_receive {:tf2_transform, ^request, {:error, :tf2_shutdown}}
        refute_receive {:tf2_transform, ^request, _}, 10
        assert :ok = Rclex.Tf2.buffer_new("crash", "node")
        assert {:ok, []} = Rclex.Tf2.list_frames("crash", "node")
      end)
    end

    test "supervised shutdown invalidates retained native buffer handles" do
      assert :ok = Rclex.Tf2.buffer_new("shutdown", "node")
      assert [{_, resource}] = :ets.lookup(@table, {"shutdown", "node", "/"})

      assert {:ok, request} =
               Rclex.Tf2.lookup_transform_async("shutdown", "map", "missing", 0, 10.0, "node")

      owner = Process.whereis(Rclex.Tf2)
      {:dictionary, dictionary} = Process.info(owner, :dictionary)
      [supervisor | _] = Keyword.fetch!(dictionary, :"$ancestors")

      try do
        assert :ok = Supervisor.terminate_child(supervisor, Rclex.Tf2)
        assert {:error, {:buffer_not_found, _}} = Rclex.Nif.tf2_clear!(resource)
        assert_receive {:tf2_transform, ^request, {:error, :tf2_shutdown}}
      after
        assert {:ok, _pid} = Supervisor.restart_child(supervisor, Rclex.Tf2)
      end
    end

    test "Tf2 public module starts automatically with the application" do
      assert is_pid(Process.whereis(Rclex.Tf2))
      assert :ok = Rclex.Tf2.buffer_new("public_api", "node")
      assert {:ok, []} = Rclex.Tf2.list_frames("public_api", "node")
      assert :ok = Rclex.Tf2.buffer_destroy("public_api", "node")
    end

    test "buffer outlives the process that created it" do
      assert :ok =
               Task.async(fn -> Rclex.Tf2.buffer_new("persistent", "node") end) |> Task.await()

      assert {:ok, []} = Rclex.Tf2.list_frames("persistent", "node")
      assert :ok = Rclex.Tf2.buffer_destroy("persistent", "node")
    end

    test "destroy invalidates native resource references retained by another caller" do
      assert :ok = Rclex.Tf2.buffer_new("native", "node")
      assert [{_, resource}] = :ets.lookup(@table, {"native", "node", "/"})
      assert :ok = Rclex.Tf2.buffer_destroy("native", "node")
      assert {:error, {:buffer_not_found, _}} = Rclex.Nif.tf2_clear!(resource)
    end

    test "creates idempotently, and destroys a buffer" do
      assert :ok = Rclex.Tf2.buffer_new("main", "node")
      assert :ok = Rclex.Tf2.buffer_new("main", "node")

      assert :ok = Rclex.Tf2.buffer_destroy("main", "node")
      assert {:error, :buffer_not_found} = Rclex.Tf2.buffer_destroy("main", "node")
    end

    test "scopes buffers by namespace with default '/'" do
      assert :ok = Rclex.Tf2.buffer_new("main", "node")
      assert :ok = Rclex.Tf2.buffer_new("main", "node", namespace: "/robot1")

      assert :ok = Rclex.Tf2.buffer_destroy("main", "node")
      assert :ok = Rclex.Tf2.buffer_destroy("main", "node", namespace: "/robot1")
    end
  end

  describe "time-aware transform behavior" do
    setup do
      assert :ok = Rclex.Tf2.buffer_new("main", "node")
      :ok
    end

    test "invalid arguments terminate a synchronous wait immediately" do
      task =
        Task.async(fn ->
          Rclex.Tf2.lookup_transform("main", "", "sensor", 0, 5.0, "node")
        end)

      assert {:error, :invalid_target_frame} = Task.await(task, 500)
    end

    test "rejects timestamps outside the ROS message range" do
      transform = stamped_transform("map", "sensor", 1, %{x: 0, y: 0, z: 0})
      transform = put_in(transform.header.stamp.nanosec, 1_000_000_000)
      assert {:error, :invalid_stamp} = Rclex.Tf2.set_transform("main", transform, "auth", "node")
    end

    test "preserves the upstream exception message on request" do
      assert {:error, {:lookup, message}} =
               Rclex.Tf2.lookup_transform("main", "map", "missing", 0, 0.0, "node",
                 error_details: true
               )

      assert message =~ "map"
    end

    test "propagates native rejection of self transforms" do
      transform = stamped_transform("map", "map", 1, %{x: 0, y: 0, z: 0})

      assert {:error, :transform_rejected} =
               Rclex.Tf2.set_transform("main", transform, "auth", "node")

      assert false == Rclex.Tf2.can_transform?("main", "map", "sensor", 0, 0.0, "node")
    end

    test "fixed-frame lookup evaluates source and target at different times" do
      for {child, stamp, offset} <- [
            {"source", 1, 3.0},
            {"source", 3, 5.0},
            {"target", 1, 10.0},
            {"target", 3, 20.0}
          ] do
        assert :ok =
                 Rclex.Tf2.set_transform(
                   "main",
                   stamped_transform("world", child, stamp, %{x: offset, y: 0.0, z: 0.0}),
                   "auth",
                   "node"
                 )
      end

      assert {:ok, found} =
               Rclex.Tf2.lookup_transform_full(
                 "main",
                 "target",
                 3_000_000_000,
                 "source",
                 1_000_000_000,
                 "world",
                 "node"
               )

      assert found.header.frame_id == "target"
      assert found.header.stamp.sec == 3
      assert_in_delta found.transform.translation.x, -17.0, 1.0e-9

      assert true ==
               Rclex.Tf2.can_transform_full?(
                 "main",
                 "target",
                 3_000_000_000,
                 "source",
                 1_000_000_000,
                 "world",
                 "node"
               )
    end

    test "concurrent writers do not lose unrelated frame samples" do
      1..40
      |> Task.async_stream(
        fn index ->
          transform = stamped_transform("world", "sensor_#{index}", 1, %{x: index, y: 0, z: 0})
          Rclex.Tf2.set_transform("main", transform, "auth", "node")
        end,
        max_concurrency: 8
      )
      |> Enum.each(fn result -> assert result == {:ok, :ok} end)

      assert {:ok, frames} = Rclex.Tf2.list_frames("main", "node")
      assert length(frames) == 40
    end

    test "returns error for invalid transform payload" do
      assert {:error, :invalid_transform_stamped} =
               Rclex.Tf2.set_transform("main", %{}, "authority", "node")
    end

    test "lookup latest with time_ns=0" do
      transform = stamped_transform("base_link", "camera_link", 10, %{x: 1.0, y: 2.0, z: 3.0})
      assert :ok = Rclex.Tf2.set_transform("main", transform, "authority", "node")

      assert {:ok, found} =
               Rclex.Tf2.lookup_transform(
                 "main",
                 "base_link",
                 "camera_link",
                 0,
                 0.0,
                 "node"
               )

      assert found.header.frame_id == "base_link"
      assert found.child_frame_id == "camera_link"
      assert found.transform.translation.x == 1.0
    end

    test "reports native extrapolation with insufficient history for a future time" do
      transform = stamped_transform("bar", "foo", 1, %{x: 2.0, y: 0.0, z: 0.0})
      assert :ok = Rclex.Tf2.set_transform("main", transform, "authority", "node")

      assert {:error, :extrapolation} =
               Rclex.Tf2.lookup_transform("main", "bar", "foo", 2_000_000_000, 0.0, "node")
    end

    test "reports native extrapolation with insufficient history for a past time" do
      transform = stamped_transform("bar", "foo", 2, %{x: 2.0, y: 0.0, z: 0.0})
      assert :ok = Rclex.Tf2.set_transform("main", transform, "authority", "node")

      assert {:error, :extrapolation} =
               Rclex.Tf2.lookup_transform("main", "bar", "foo", 1_000_000_000, 0.0, "node")
    end

    test "can_transform? returns boolean and optional debug tuple" do
      transform = stamped_transform("map", "odom", 1, %{x: 0.0, y: 0.0, z: 0.0})
      assert :ok = Rclex.Tf2.set_transform("main", transform, "authority", "node")

      assert true == Rclex.Tf2.can_transform?("main", "map", "odom", 0, 0.0, "node")

      assert {false, reason} =
               Rclex.Tf2.can_transform?(
                 "main",
                 "map",
                 "base_link",
                 0,
                 0.0,
                 "node",
                 return_debug_tuple: true
               )

      assert is_binary(reason)
    end

    test "set_transform_static is valid for future time" do
      transform = stamped_transform("world", "sensor", 0, %{x: 1.0, y: 0.0, z: 0.0})
      assert :ok = Rclex.Tf2.set_transform_static("main", transform, "authority", "node")

      assert {:ok, found} =
               Rclex.Tf2.lookup_transform(
                 "main",
                 "world",
                 "sensor",
                 99_000_000_000,
                 0.0,
                 "node"
               )

      assert_in_delta found.transform.translation.x, 1.0, 1.0e-6
    end

    test "returns latest common time" do
      assert :ok =
               Rclex.Tf2.set_transform(
                 "main",
                 stamped_transform("map", "odom", 1, %{x: 0.0, y: 0.0, z: 0.0}),
                 "authority",
                 "node"
               )

      assert :ok =
               Rclex.Tf2.set_transform(
                 "main",
                 stamped_transform("odom", "base_link", 3, %{x: 0.0, y: 0.0, z: 0.0}),
                 "authority",
                 "node"
               )

      assert {:ok, latest_ns} =
               Rclex.Tf2.get_latest_common_time("main", "map", "base_link", "node")

      assert latest_ns == 1_000_000_000
    end

    test "clear removes dynamic samples but preserves static transforms" do
      assert :ok =
               Rclex.Tf2.set_transform_static(
                 "main",
                 stamped_transform("world", "sensor", 0, %{x: 1.0, y: 0.0, z: 0.0}),
                 "authority",
                 "node"
               )

      assert :ok =
               Rclex.Tf2.set_transform(
                 "main",
                 stamped_transform("map", "odom", 1, %{x: 0.0, y: 0.0, z: 0.0}),
                 "authority",
                 "node"
               )

      assert :ok =
               Rclex.Tf2.set_transform(
                 "main",
                 stamped_transform("odom", "base_link", 3, %{x: 0.0, y: 0.0, z: 0.0}),
                 "authority",
                 "node"
               )

      assert {:ok, yaml_before} = Rclex.Tf2.all_frames_as_yaml("main", "node")
      assert yaml_before =~ "map"
      assert yaml_before =~ "parent:"
      assert yaml_before =~ "broadcaster:"
      assert yaml_before =~ "most_recent_transform:"

      assert :ok = Rclex.Tf2.clear("main", "node")

      assert {:ok, yaml_after} = Rclex.Tf2.all_frames_as_yaml("main", "node")
      assert yaml_after =~ "sensor"
      refute yaml_after =~ "base_link"
      assert {:error, _} = Rclex.Tf2.lookup_transform("main", "map", "odom", 0, 0.0, "node")

      assert {:ok, found} =
               Rclex.Tf2.lookup_transform("main", "world", "sensor", 9_000_000_000, 0.0, "node")

      assert found.transform.translation.x == 1.0
    end
  end

  describe "example calculations" do
    setup do
      assert :ok = Rclex.Tf2.buffer_new("main", "node")
      :ok
    end

    test "example calculation: quaternion represents 90 degree yaw" do
      half_pi = :math.pi() / 2.0
      half_angle = half_pi / 2.0

      transform =
        stamped_transform(
          "map",
          "base_link",
          10,
          %{x: 1.0, y: 0.0, z: 0.0},
          %{w: :math.cos(half_angle), x: 0.0, y: 0.0, z: :math.sin(half_angle)}
        )

      assert :ok = Rclex.Tf2.set_transform("main", transform, "authority", "node")

      assert {:ok, found} =
               Rclex.Tf2.lookup_transform(
                 "main",
                 "map",
                 "base_link",
                 10_000_000_000,
                 0.0,
                 "node"
               )

      rotation = found.transform.rotation
      yaw = quaternion_to_yaw(rotation)

      assert_in_delta yaw, half_pi, 1.0e-6
    end

    test "example calculation with multiple links in between" do
      assert :ok =
               Rclex.Tf2.set_transform(
                 "main",
                 stamped_transform("map", "odom", 10, %{x: 1.0, y: 0.0, z: 0.0}),
                 "authority",
                 "node"
               )

      assert :ok =
               Rclex.Tf2.set_transform(
                 "main",
                 stamped_transform("odom", "base_link", 10, %{x: 0.0, y: 2.0, z: 0.0}),
                 "authority",
                 "node"
               )

      assert :ok =
               Rclex.Tf2.set_transform(
                 "main",
                 stamped_transform("base_link", "camera_link", 10, %{x: 0.0, y: 0.0, z: 3.0}),
                 "authority",
                 "node"
               )

      assert {:ok, found} =
               Rclex.Tf2.lookup_transform(
                 "main",
                 "map",
                 "camera_link",
                 10_000_000_000,
                 0.0,
                 "node"
               )

      assert found.header.frame_id == "map"
      assert found.child_frame_id == "camera_link"
      assert_in_delta found.transform.translation.x, 1.0, 1.0e-6
      assert_in_delta found.transform.translation.y, 2.0, 1.0e-6
      assert_in_delta found.transform.translation.z, 3.0, 1.0e-6
    end
  end

  describe "clock-bound buffers" do
    setup do
      clock = start_supervised!({Rclex.Clock, name: :tf2_test_clock, clock_type: :ros_time})
      assert :ok = Rclex.Clock.enable_ros_time_override(clock)
      assert :ok = Rclex.Clock.set_ros_time_override(clock, 10_000_000_000)
      assert :ok = Rclex.Tf2.buffer_new("clocked", "node", clock: clock)

      on_exit(fn -> Rclex.Tf2.buffer_destroy("clocked", "node") end)
      %{clock: clock}
    end

    test "destroy releases the clock registration and allows rebinding", %{clock: clock} do
      owner = Process.whereis(Rclex.Tf2)
      assert {:monitors, [{:process, ^owner}]} = Process.info(clock, :monitors)
      assert :ok = Rclex.Tf2.buffer_destroy("clocked", "node")
      assert {:monitors, []} = Process.info(clock, :monitors)
      assert :ok = Rclex.Tf2.buffer_new("clocked", "node", clock: clock)
      assert {:monitors, [{:process, ^owner}]} = Process.info(clock, :monitors)
    end

    test "backward jumps clear dynamic history but preserve static data", %{clock: clock} do
      assert :ok =
               Rclex.Tf2.set_transform(
                 "clocked",
                 stamped_transform("map", "odom", 10, %{x: 1, y: 0, z: 0}),
                 "auth",
                 "node"
               )

      assert :ok =
               Rclex.Tf2.set_transform_static(
                 "clocked",
                 stamped_transform("map", "sensor", 0, %{x: 2, y: 0, z: 0}),
                 "auth",
                 "node"
               )

      assert :ok = Rclex.Clock.set_ros_time_override(clock, 9_999_999_999)

      assert false == Rclex.Tf2.can_transform?("clocked", "map", "odom", 0, 0.0, "node")
      assert true == Rclex.Tf2.can_transform?("clocked", "map", "sensor", 0, 0.0, "node")
    end

    test "forward jumps do not clear dynamic history", %{clock: clock} do
      assert :ok =
               Rclex.Tf2.set_transform(
                 "clocked",
                 stamped_transform("map", "odom", 10, %{x: 1, y: 0, z: 0}),
                 "auth",
                 "node"
               )

      assert :ok = Rclex.Clock.set_ros_time_override(clock, 20_000_000_000)
      assert true == Rclex.Tf2.can_transform?("clocked", "map", "odom", 0, 0.0, "node")
    end

    test "ROS time activation and deactivation clear dynamic history", %{clock: clock} do
      for change <- [
            &Rclex.Clock.disable_ros_time_override/1,
            &Rclex.Clock.enable_ros_time_override/1
          ] do
        assert :ok =
                 Rclex.Tf2.set_transform(
                   "clocked",
                   stamped_transform("map", "odom", 10, %{x: 1, y: 0, z: 0}),
                   "auth",
                   "node"
                 )

        assert :ok = change.(clock)
        assert false == Rclex.Tf2.can_transform?("clocked", "map", "odom", 0, 0.0, "node")
      end
    end
  end

  describe "asynchronous waits" do
    setup do
      assert :ok = Rclex.Tf2.buffer_new("async", "node")
      on_exit(fn -> Rclex.Tf2.buffer_destroy("async", "node") end)
      :ok
    end

    test "a busy cleanup owner does not cause duplicate async replies" do
      assert {:ok, request} =
               Rclex.Tf2.lookup_transform_async("async", "map", "sensor", 0, 10.0, "node")

      cleanup = Process.whereis(Rclex.Tf2.Cleanup)
      :ok = :sys.suspend(cleanup)

      try do
        assert :ok =
                 Rclex.Tf2.set_transform_static(
                   "async",
                   stamped_transform("map", "sensor", 0, %{x: 4, y: 0, z: 0}),
                   "auth",
                   "node"
                 )

        refute_receive {:tf2_transform, ^request, _}, 5_500
      after
        :ok = :sys.resume(cleanup)
      end

      assert_receive {:tf2_transform, ^request, {:ok, _}}, 1_000
      refute_receive {:tf2_transform, ^request, _}, 20
    end

    test "fixed-frame async lookup rechecks both time-qualified paths" do
      assert {:ok, request} =
               Rclex.Tf2.lookup_transform_full_async(
                 "async",
                 "target",
                 2_000_000_000,
                 "source",
                 1_000_000_000,
                 "world",
                 "node",
                 timeout_sec: 1.0
               )

      assert :ok =
               Rclex.Tf2.set_transform_static(
                 "async",
                 stamped_transform("world", "target", 0, %{x: 10, y: 0, z: 0}),
                 "auth",
                 "node"
               )

      assert :ok =
               Rclex.Tf2.set_transform_static(
                 "async",
                 stamped_transform("world", "source", 0, %{x: 3, y: 0, z: 0}),
                 "auth",
                 "node"
               )

      assert_receive {:tf2_transform, ^request, {:ok, found}}
      assert found.header.stamp.sec == 2
      assert_in_delta found.transform.translation.x, -7.0, 1.0e-9
    end

    test "completes when a transform is inserted" do
      assert {:ok, request} =
               Rclex.Tf2.lookup_transform_async("async", "map", "sensor", 0, 1.0, "node")

      refute_receive {:tf2_transform, ^request, _}, 10

      assert :ok =
               Rclex.Tf2.set_transform(
                 "async",
                 stamped_transform("map", "sensor", 1, %{x: 4, y: 0, z: 0}),
                 "auth",
                 "node"
               )

      assert_receive {:tf2_transform, ^request, {:ok, found}}
      assert found.transform.translation.x == 4.0
    end

    test "completes immediately when the transform already exists" do
      assert :ok =
               Rclex.Tf2.set_transform_static(
                 "async",
                 stamped_transform("map", "sensor", 0, %{x: 4, y: 0, z: 0}),
                 "auth",
                 "node"
               )

      assert {:ok, request} =
               Rclex.Tf2.lookup_transform_async("async", "map", "sensor", 0, 1.0, "node")

      assert_receive {:tf2_transform, ^request, {:ok, _}}
    end

    test "cancellation prevents subsequent delivery" do
      assert {:ok, request} =
               Rclex.Tf2.lookup_transform_async("async", "map", "sensor", 0, 1.0, "node")

      assert :ok = Rclex.Tf2.cancel_wait(request)

      assert :ok =
               Rclex.Tf2.set_transform_static(
                 "async",
                 stamped_transform("map", "sensor", 0, %{x: 4, y: 0, z: 0}),
                 "auth",
                 "node"
               )

      refute_receive {:tf2_transform, ^request, _}, 30
    end

    test "uses a wall-time deadline even when ROS time is paused" do
      clock = start_supervised!({Rclex.Clock, name: :tf2_async_clock, clock_type: :ros_time})
      assert :ok = Rclex.Clock.enable_ros_time_override(clock)
      assert :ok = Rclex.Tf2.buffer_new("paused", "node", clock: clock)

      assert {:ok, request} =
               Rclex.Tf2.lookup_transform_async("paused", "map", "sensor", 0, 0.02, "node")

      assert_receive {:tf2_transform, ^request, {:error, :timeout}}, 500
      assert :ok = Rclex.Tf2.buffer_destroy("paused", "node")
    end

    test "destroy resolves pending waits with buffer_not_found" do
      assert {:ok, request} =
               Rclex.Tf2.lookup_transform_async("async", "map", "sensor", 0, 1.0, "node")

      assert :ok = Rclex.Tf2.buffer_destroy("async", "node")
      assert_receive {:tf2_transform, ^request, {:error, :buffer_not_found}}
    end

    test "removes waits when their caller exits" do
      assert {:ok, _request} =
               Task.async(fn ->
                 Rclex.Tf2.lookup_transform_async("async", "map", "sensor", 0, 10.0, "node")
               end)
               |> Task.await()

      assert %{pending: pending} = :sys.get_state(Rclex.Tf2)
      assert map_size(pending) == 0
    end
  end

  describe "native stamped geometry conversions" do
    setup do
      assert :ok = Rclex.Tf2.buffer_new("geometry", "node")
      half_angle = :math.pi() / 4

      transform =
        stamped_transform("map", "sensor", 1, %{x: 10, y: 0, z: 0}, %{
          x: 0,
          y: 0,
          z: :math.sin(half_angle),
          w: :math.cos(half_angle)
        })

      assert :ok = Rclex.Tf2.set_transform_static("geometry", transform, "auth", "node")
      %{header: %{frame_id: "sensor", stamp: %{sec: 2, nanosec: 7}}}
    end

    test "points translate and rotate, while vectors only rotate", %{header: header} do
      for kind <- [:point, :vector] do
        input = %{kind => %{x: 1.0, y: 0.0, z: 0.0}, :header => header}
        assert {:ok, result} = Rclex.Tf2.transform("geometry", input, "map", "node")
        assert result.header == %{header | frame_id: "map"}
        assert_in_delta result[kind].x, if(kind == :point, do: 10.0, else: 0.0), 1.0e-9
        assert_in_delta result[kind].y, 1.0, 1.0e-9
      end
    end

    test "quaternion, pose and transform stamped use upstream composition", %{header: header} do
      identity = %{x: 0.0, y: 0.0, z: 0.0, w: 1.0}

      assert {:ok, quaternion} =
               Rclex.Tf2.transform(
                 "geometry",
                 %{header: header, quaternion: identity},
                 "map",
                 "node"
               )

      assert_in_delta quaternion_to_yaw(quaternion.quaternion), :math.pi() / 2, 1.0e-9

      pose = %{
        header: header,
        pose: %{position: %{x: 1.0, y: 0.0, z: 0.0}, orientation: identity}
      }

      assert {:ok, result} = Rclex.Tf2.transform("geometry", pose, "map", "node")
      assert_in_delta result.pose.position.x, 10.0, 1.0e-9
      assert_in_delta result.pose.position.y, 1.0, 1.0e-9

      transform = stamped_transform("sensor", "tool", 2, %{x: 1, y: 0, z: 0})
      assert {:ok, result} = Rclex.Tf2.transform("geometry", transform, "map", "node")
      assert result.child_frame_id == "tool"
      assert_in_delta result.transform.translation.x, 10.0, 1.0e-9
      assert_in_delta result.transform.translation.y, 1.0, 1.0e-9
    end

    test "preserves generated message struct types" do
      input = %TransformStamped{
        header: %Header{frame_id: "sensor", stamp: %Time{sec: 2}},
        child_frame_id: "tool",
        transform: %Transform{translation: %Vector3{x: 1.0}, rotation: %Quaternion{w: 1.0}}
      }

      assert {:ok,
              %TransformStamped{header: %Header{}, transform: %Transform{translation: %Vector3{}}}} =
               Rclex.Tf2.transform("geometry", input, "map", "node")
    end
  end

  describe "transport wiring guard rails" do
    setup do
      assert :ok = Rclex.Tf2.buffer_new("main", "node")
      :ok
    end

    test "listener and broadcaster report missing tf message type module" do
      missing = Rclex.Pkgs.Tf2Msgs.Msg.MissingTFMessage

      assert {:error, {:tf_message_type_not_generated, _}} =
               Rclex.Tf2.start_listener("main", "node", tf_message_type_module: missing)

      assert {:error, {:tf_message_type_not_generated, _}} =
               Rclex.Tf2.start_broadcaster("node", tf_message_type_module: missing)
    end

    test "broadcast helpers report missing tf message type module" do
      missing = Rclex.Pkgs.Tf2Msgs.Msg.MissingTFMessage

      transform =
        stamped_transform("map", "base_link", 1, %{x: 0.0, y: 0.0, z: 0.0})

      assert {:error, {:tf_message_type_not_generated, _}} =
               Rclex.Tf2.broadcast_dynamic(transform, "node", tf_message_type_module: missing)

      assert {:error, {:tf_message_type_not_generated, _}} =
               Rclex.Tf2.broadcast_static(transform, "node", tf_message_type_module: missing)
    end
  end

  describe "transport wiring end-to-end" do
    setup do
      :ok = Application.ensure_started(:rclex)

      name = "tf_wire_node"
      namespace = "/"

      assert :ok = Rclex.start_node(name, namespace: namespace)
      assert :ok = Rclex.Tf2.buffer_new("main", name, namespace: namespace)

      on_exit(fn ->
        _ =
          capture_log(fn ->
            _ = Rclex.Tf2.stop_listener("main", name, namespace: namespace)
            _ = Rclex.Tf2.stop_broadcaster(name, namespace: namespace)
            _ = Rclex.Tf2.buffer_destroy("main", name, namespace: namespace)
            _ = Rclex.stop_node(name, namespace: namespace)
          end)
      end)

      %{name: name, namespace: namespace}
    end

    test "supervised shutdown stops transport and unregisters clock bindings", %{name: name} do
      clock = start_supervised!({Rclex.Clock, name: :tf2_shutdown_clock, clock_type: :ros_time})
      assert :ok = Rclex.Tf2.buffer_new("clock_shutdown", name, clock: clock)
      assert :ok = Rclex.Tf2.start_listener("clock_shutdown", name)
      assert :ok = Rclex.Tf2.start_broadcaster(name)
      owner = Process.whereis(Rclex.Tf2)
      {:dictionary, dictionary} = Process.info(owner, :dictionary)
      [supervisor | _] = Keyword.fetch!(dictionary, :"$ancestors")
      message_type = Rclex.Pkgs.Tf2Msgs.Msg.TFMessage

      capture_log(fn ->
        try do
          assert :ok = Supervisor.terminate_child(supervisor, Rclex.Tf2)
          assert {:monitors, []} = Process.info(clock, :monitors)

          for topic <- ["/tf", "/tf_static"] do
            assert {:error, :not_found} = Rclex.stop_subscription(message_type, topic, name)
            assert {:error, :not_found} = Rclex.stop_publisher(message_type, topic, name)
          end
        after
          assert {:ok, _pid} = Supervisor.restart_child(supervisor, Rclex.Tf2)
        end
      end)
    end

    test "abrupt restart stops transport owned by the previous generation", %{name: name} do
      assert :ok = Rclex.Tf2.start_listener("main", name)
      assert :ok = Rclex.Tf2.start_broadcaster(name)
      owner = Process.whereis(Rclex.Tf2)
      message_type = Rclex.Pkgs.Tf2Msgs.Msg.TFMessage

      capture_log(fn ->
        Process.exit(owner, :kill)
        new_owner = await_tf2_restart(owner)
        assert :ok = GenServer.call(new_owner, :ensure_table)

        for topic <- ["/tf", "/tf_static"] do
          assert {:error, :not_found} = Rclex.stop_subscription(message_type, topic, name)
          assert {:error, :not_found} = Rclex.stop_publisher(message_type, topic, name)
        end
      end)
    end

    test "failed transport starts preserve other buffers and can be retried", %{name: name} do
      late_node = "late_tf_wire_node"
      assert :ok = Rclex.Tf2.buffer_new("retry", late_node)

      on_exit(fn ->
        capture_log(fn ->
          Rclex.Tf2.buffer_destroy("retry", late_node)
          Rclex.stop_node(late_node)
        end)
      end)

      assert {:error, _} = Rclex.Tf2.start_listener("retry", late_node)
      assert {:error, _} = Rclex.Tf2.start_broadcaster(late_node)
      assert {:ok, []} = Rclex.Tf2.list_frames("main", name)
      assert :ok = Rclex.start_node(late_node)
      assert :ok = Rclex.Tf2.start_listener("retry", late_node)
      assert :ok = Rclex.Tf2.start_broadcaster(late_node)
    end

    test "concurrent lifecycle calls are idempotent and transport can restart", %{name: name} do
      for operation <- [
            fn -> Rclex.Tf2.start_listener("main", name) end,
            fn -> Rclex.Tf2.start_broadcaster(name) end,
            fn -> Rclex.Tf2.stop_listener("main", name) end,
            fn -> Rclex.Tf2.stop_broadcaster(name) end
          ] do
        1..8
        |> Task.async_stream(fn _index -> operation.() end, max_concurrency: 8)
        |> Enum.each(fn result -> assert result == {:ok, :ok} end)
      end

      assert :ok = Rclex.Tf2.start_listener("main", name)
      assert :ok = Rclex.Tf2.start_broadcaster(name)

      transform = %TransformStamped{
        header: %Header{frame_id: "restart_world", stamp: %Time{}},
        child_frame_id: "restart_sensor",
        transform: %Transform{translation: %Vector3{x: 4.0}, rotation: %Quaternion{w: 1.0}}
      }

      assert :ok = Rclex.Tf2.broadcast_static(transform, name)

      assert {:ok, found} =
               Rclex.Tf2.lookup_transform("main", "restart_world", "restart_sensor", 0, 1.0, name)

      assert found.transform.translation.x == 4.0
    end

    test "late listeners receive retained static transforms", %{name: name} do
      assert :ok = Rclex.Tf2.start_broadcaster(name)

      transform = %TransformStamped{
        header: %Header{frame_id: "static_world", stamp: %Time{}},
        child_frame_id: "static_sensor",
        transform: %Transform{translation: %Vector3{x: 3.0}, rotation: %Quaternion{w: 1.0}}
      }

      assert :ok = Rclex.Tf2.broadcast_static(transform, name)
      assert :ok = Rclex.Tf2.start_listener("main", name)

      assert {:ok, found} =
               Rclex.Tf2.lookup_transform("main", "static_world", "static_sensor", 0, 1.0, name)

      assert found.transform.translation.x == 3.0
    end

    test "broadcast_dynamic is ingested by listener and available for lookup", %{
      name: name,
      namespace: namespace
    } do
      assert :ok = Rclex.Tf2.start_listener("main", name, namespace: namespace)
      assert :ok = Rclex.Tf2.start_broadcaster(name, namespace: namespace)

      ts = %TransformStamped{
        header: %Header{frame_id: "map", stamp: %Time{sec: 42, nanosec: 0}},
        child_frame_id: "base_link",
        transform: %Transform{
          translation: %Vector3{x: 1.0, y: 2.0, z: 3.0},
          rotation: %Quaternion{w: 1.0, x: 0.0, y: 0.0, z: 0.0}
        }
      }

      assert :ok = Rclex.Tf2.broadcast_dynamic(ts, name, namespace: namespace)

      assert {:ok, found} =
               Rclex.Tf2.lookup_transform(
                 "main",
                 "map",
                 "base_link",
                 42_000_000_000,
                 0.5,
                 name,
                 namespace: namespace
               )

      assert found.header.frame_id == "map"
      assert found.child_frame_id == "base_link"
      assert_in_delta found.transform.translation.x, 1.0, 1.0e-6
      assert_in_delta found.transform.translation.y, 2.0, 1.0e-6
      assert_in_delta found.transform.translation.z, 3.0, 1.0e-6
    end
  end

  defp quaternion_to_yaw(%{w: w, x: x, y: y, z: z}) do
    siny_cosp = 2.0 * (w * z + x * y)
    cosy_cosp = 1.0 - 2.0 * (y * y + z * z)
    :math.atan2(siny_cosp, cosy_cosp)
  end

  defp await_tf2_restart(previous, attempts \\ 100)
  defp await_tf2_restart(_previous, 0), do: flunk("Tf2 did not restart")

  defp await_tf2_restart(previous, attempts) do
    case Process.whereis(Rclex.Tf2) do
      pid when is_pid(pid) and pid != previous ->
        pid

      _ ->
        Process.sleep(10)
        await_tf2_restart(previous, attempts - 1)
    end
  end

  describe "operations on missing buffer" do
    test "returns :buffer_not_found for clear/lookup/all_frames/get_latest_common_time/can_transform?/set_transform" do
      assert {:error, :buffer_not_found} = Rclex.Tf2.clear("absent", "node")
      assert {:error, :buffer_not_found} = Rclex.Tf2.all_frames_as_yaml("absent", "node")

      assert {:error, :buffer_not_found} =
               Rclex.Tf2.lookup_transform("absent", "a", "b", 0, 0.0, "node")

      assert {:error, :buffer_not_found} =
               Rclex.Tf2.get_latest_common_time("absent", "a", "b", "node")

      assert {:error, :buffer_not_found} =
               Rclex.Tf2.can_transform?("absent", "a", "b", 0, 0.0, "node")

      transform =
        %{
          header: %{frame_id: "a", stamp: %{sec: 0, nanosec: 0}},
          child_frame_id: "b",
          transform: %{
            translation: %{x: 0.0, y: 0.0, z: 0.0},
            rotation: %{w: 1.0, x: 0.0, y: 0.0, z: 0.0}
          }
        }

      assert {:error, :buffer_not_found} =
               Rclex.Tf2.set_transform("absent", transform, "auth", "node")
    end
  end

  describe "validation errors" do
    setup do
      assert :ok = Rclex.Tf2.buffer_new("main", "node")
      :ok
    end

    test "invalid frame ids when looking up" do
      transform = stamped_transform("a", "b", 1, %{x: 0.0, y: 0.0, z: 0.0})
      assert :ok = Rclex.Tf2.set_transform("main", transform, "auth", "node")

      assert {:error, :invalid_target_frame} =
               Rclex.Tf2.lookup_transform("main", "", "b", 0, 0.0, "node")

      assert {:error, :invalid_source_frame} =
               Rclex.Tf2.lookup_transform("main", "a", "  ", 0, 0.0, "node")

      assert {:error, :invalid_target_frame} =
               Rclex.Tf2.get_latest_common_time("main", "", "b", "node")
    end

    test "invalid translation/rotation in transform payload" do
      bad_translation =
        %{
          header: %{frame_id: "a", stamp: %{sec: 0, nanosec: 0}},
          child_frame_id: "b",
          transform: %{
            translation: %{x: "nope", y: 0.0, z: 0.0},
            rotation: %{w: 1.0, x: 0.0, y: 0.0, z: 0.0}
          }
        }

      assert {:error, :invalid_transform_stamped} =
               Rclex.Tf2.set_transform("main", bad_translation, "auth", "node")

      bad_rotation =
        %{
          header: %{frame_id: "a", stamp: %{sec: 0, nanosec: 0}},
          child_frame_id: "b",
          transform: %{
            translation: %{x: 0.0, y: 0.0, z: 0.0},
            rotation: %{w: 0.0, x: 0.0, y: 0.0, z: 0.0}
          }
        }

      assert {:error, :invalid_quaternion} =
               Rclex.Tf2.set_transform("main", bad_rotation, "auth", "node")
    end

    test "invalid stamp" do
      bad_stamp =
        %{
          header: %{frame_id: "a", stamp: %{sec: -1, nanosec: 0}},
          child_frame_id: "b",
          transform: %{
            translation: %{x: 0.0, y: 0.0, z: 0.0},
            rotation: %{w: 1.0, x: 0.0, y: 0.0, z: 0.0}
          }
        }

      assert {:error, :invalid_stamp} =
               Rclex.Tf2.set_transform("main", bad_stamp, "auth", "node")
    end

    test "lookup with unknown frame returns :lookup" do
      transform = stamped_transform("a", "b", 1, %{x: 0.0, y: 0.0, z: 0.0})
      assert :ok = Rclex.Tf2.set_transform("main", transform, "auth", "node")

      assert {:error, :lookup} =
               Rclex.Tf2.lookup_transform("main", "a", "z", 0, 0.0, "node")
    end

    test "can_transform? debug tuple succeeds with empty reason" do
      transform = stamped_transform("a", "b", 1, %{x: 0.0, y: 0.0, z: 0.0})
      assert :ok = Rclex.Tf2.set_transform("main", transform, "auth", "node")

      assert {true, ""} =
               Rclex.Tf2.can_transform?("main", "a", "b", 0, 0.0, "node",
                 return_debug_tuple: true
               )
    end
  end

  describe "interpolation and extrapolation" do
    setup do
      assert :ok = Rclex.Tf2.buffer_new("main", "node")

      :ok =
        Rclex.Tf2.set_transform(
          "main",
          stamped_transform("a", "b", 1, %{x: 0.0, y: 0.0, z: 0.0}),
          "auth",
          "node"
        )

      :ok =
        Rclex.Tf2.set_transform(
          "main",
          stamped_transform("a", "b", 3, %{x: 2.0, y: 0.0, z: 0.0}),
          "auth",
          "node"
        )

      :ok
    end

    test "interpolates between two stamps" do
      assert {:ok, found} =
               Rclex.Tf2.lookup_transform("main", "a", "b", 2_000_000_000, 0.0, "node")

      assert_in_delta found.transform.translation.x, 1.0, 1.0e-6
      assert found.header.stamp.sec == 2
    end

    test "exact-stamp lookup returns that sample" do
      assert {:ok, found} =
               Rclex.Tf2.lookup_transform("main", "a", "b", 1_000_000_000, 0.0, "node")

      assert_in_delta found.transform.translation.x, 0.0, 1.0e-6
    end

    test "extrapolation in past below first sample" do
      assert {:error, :extrapolation_past} =
               Rclex.Tf2.lookup_transform("main", "a", "b", 500_000_000, 0.0, "node")
    end

    test "extrapolation in future above last sample" do
      assert {:error, :extrapolation_future} =
               Rclex.Tf2.lookup_transform("main", "a", "b", 5_000_000_000, 0.0, "node")
    end
  end

  describe "slerp interpolation" do
    setup do
      assert :ok = Rclex.Tf2.buffer_new("main", "node")
      :ok
    end

    test "interpolates rotation halfway between 0 and 90 deg yaw" do
      half_pi = :math.pi() / 2.0
      half_angle = half_pi / 2.0

      :ok =
        Rclex.Tf2.set_transform(
          "main",
          stamped_transform("a", "b", 1, %{x: 0.0, y: 0.0, z: 0.0}, %{
            w: 1.0,
            x: 0.0,
            y: 0.0,
            z: 0.0
          }),
          "auth",
          "node"
        )

      :ok =
        Rclex.Tf2.set_transform(
          "main",
          stamped_transform("a", "b", 3, %{x: 0.0, y: 0.0, z: 0.0}, %{
            w: :math.cos(half_angle),
            x: 0.0,
            y: 0.0,
            z: :math.sin(half_angle)
          }),
          "auth",
          "node"
        )

      assert {:ok, found} =
               Rclex.Tf2.lookup_transform("main", "a", "b", 2_000_000_000, 0.0, "node")

      yaw = quaternion_to_yaw(found.transform.rotation)
      # Halfway should be about pi/4
      assert_in_delta yaw, half_pi / 2.0, 1.0e-3
    end
  end

  describe "broadcast helpers without active publisher" do
    test "broadcast_dynamic with default tf message type but no publisher returns error" do
      transform = stamped_transform("a", "b", 1, %{x: 0.0, y: 0.0, z: 0.0})

      result = Rclex.Tf2.broadcast_dynamic(transform, "no_such_node")
      assert match?({:error, _}, result)
    end

    test "broadcast_static with list works through normalization" do
      transform = stamped_transform("a", "b", 1, %{x: 0.0, y: 0.0, z: 0.0})

      result = Rclex.Tf2.broadcast_static([transform], "no_such_node")
      assert match?({:error, _}, result)
    end
  end

  describe "namespace scoping" do
    test "lookup is isolated per namespace" do
      :ok = Rclex.Tf2.buffer_new("main", "node", namespace: "/ns_a")
      :ok = Rclex.Tf2.buffer_new("main", "node", namespace: "/ns_b")

      :ok =
        Rclex.Tf2.set_transform(
          "main",
          stamped_transform("a", "b", 1, %{x: 1.0, y: 0.0, z: 0.0}),
          "auth",
          "node",
          namespace: "/ns_a"
        )

      assert {:error, :lookup} =
               Rclex.Tf2.lookup_transform(
                 "main",
                 "a",
                 "b",
                 0,
                 0.0,
                 "node",
                 namespace: "/ns_b"
               )

      assert {:ok, found} =
               Rclex.Tf2.lookup_transform(
                 "main",
                 "a",
                 "b",
                 0,
                 0.0,
                 "node",
                 namespace: "/ns_a"
               )

      assert_in_delta found.transform.translation.x, 1.0, 1.0e-6

      _ = Rclex.Tf2.buffer_destroy("main", "node", namespace: "/ns_a")
      _ = Rclex.Tf2.buffer_destroy("main", "node", namespace: "/ns_b")
    end
  end

  describe "transitive transform via reverse edges" do
    setup do
      assert :ok = Rclex.Tf2.buffer_new("main", "node")
      :ok
    end

    test "lookups walk reverse edges through inverted transforms" do
      :ok =
        Rclex.Tf2.set_transform(
          "main",
          stamped_transform("map", "odom", 10, %{x: 1.0, y: 0.0, z: 0.0}),
          "auth",
          "node"
        )

      :ok =
        Rclex.Tf2.set_transform(
          "main",
          stamped_transform("map", "base_link", 10, %{x: 0.0, y: 5.0, z: 0.0}),
          "auth",
          "node"
        )

      assert {:ok, found} =
               Rclex.Tf2.lookup_transform(
                 "main",
                 "odom",
                 "base_link",
                 10_000_000_000,
                 0.0,
                 "node"
               )

      assert_in_delta found.transform.translation.x, -1.0, 1.0e-6
      assert_in_delta found.transform.translation.y, 5.0, 1.0e-6
    end
  end

  describe "extra branches" do
    setup do
      assert :ok = Rclex.Tf2.buffer_new("main", "node")
      :ok
    end

    test "buffer_destroy on existing buffer also clears state" do
      :ok =
        Rclex.Tf2.set_transform(
          "main",
          stamped_transform("a", "b", 1, %{x: 0.0, y: 0.0, z: 0.0}),
          "auth",
          "node"
        )

      :ok = Rclex.Tf2.buffer_destroy("main", "node")
      :ok = Rclex.Tf2.buffer_new("main", "node")

      assert {:ok, "[]"} = Rclex.Tf2.all_frames_as_yaml("main", "node")
    end

    test "set_transform_static with cache_time_sec=0 keeps only latest" do
      :ok = Rclex.Tf2.buffer_destroy("main", "node")
      :ok = Rclex.Tf2.buffer_new("main", "node", cache_time_sec: 0.0)

      :ok =
        Rclex.Tf2.set_transform(
          "main",
          stamped_transform("a", "b", 1, %{x: 0.0, y: 0.0, z: 0.0}),
          "auth",
          "node"
        )

      :ok =
        Rclex.Tf2.set_transform(
          "main",
          stamped_transform("a", "b", 5, %{x: 1.0, y: 0.0, z: 0.0}),
          "auth",
          "node"
        )

      # With cache_time_ns == 0, only the latest is kept. So lookup at
      # latest stamp returns the latest transform.
      assert {:ok, found} =
               Rclex.Tf2.lookup_transform("main", "a", "b", 5_000_000_000, 0.0, "node")

      assert_in_delta found.transform.translation.x, 1.0, 1.0e-6
    end

    test "duplicate-stamp samples are deduped" do
      :ok =
        Rclex.Tf2.set_transform(
          "main",
          stamped_transform("a", "b", 1, %{x: 1.0, y: 0.0, z: 0.0}),
          "auth",
          "node"
        )

      :ok =
        Rclex.Tf2.set_transform(
          "main",
          stamped_transform("a", "b", 1, %{x: 9.0, y: 0.0, z: 0.0}),
          "auth",
          "node"
        )

      assert {:ok, found} =
               Rclex.Tf2.lookup_transform("main", "a", "b", 1_000_000_000, 0.0, "node")

      assert_in_delta found.transform.translation.x, 9.0, 1.0e-6
    end

    test "yaml output preserves the native empty broadcaster" do
      :ok =
        Rclex.Tf2.set_transform(
          "main",
          stamped_transform("a", "b", 1, %{x: 0.0, y: 0.0, z: 0.0}),
          "",
          "node"
        )

      assert {:ok, yaml} = Rclex.Tf2.all_frames_as_yaml("main", "node")
      assert yaml =~ "broadcaster: ''"
    end
  end

  describe "list_frames/3" do
    setup do
      assert :ok = Rclex.Tf2.buffer_new("main", "node")
      :ok
    end

    test "returns an empty list for an empty buffer" do
      assert {:ok, []} = Rclex.Tf2.list_frames("main", "node")
    end

    test "returns structured entries matching the yaml rendering" do
      :ok =
        Rclex.Tf2.set_transform(
          "main",
          stamped_transform("map", "odom", 1, %{x: 0.0, y: 0.0, z: 0.0}),
          "authority",
          "node"
        )

      assert {:ok, [frame]} = Rclex.Tf2.list_frames("main", "node")
      assert frame.child == "odom"
      assert frame.parent == "map"
      assert frame.broadcaster == "authority"
      assert is_float(frame.rate)
      assert is_float(frame.most_recent_transform)
      assert is_float(frame.oldest_transform)
      assert is_float(frame.buffer_length)

      assert {:ok, yaml} = Rclex.Tf2.all_frames_as_yaml("main", "node")
      assert yaml =~ "odom:"
      assert yaml =~ "  parent: 'map'"
    end

    test "sorts entries by child frame name" do
      :ok =
        Rclex.Tf2.set_transform(
          "main",
          stamped_transform("map", "zeta", 1, %{x: 0.0, y: 0.0, z: 0.0}),
          "authority",
          "node"
        )

      :ok =
        Rclex.Tf2.set_transform(
          "main",
          stamped_transform("map", "alpha", 1, %{x: 0.0, y: 0.0, z: 0.0}),
          "authority",
          "node"
        )

      assert {:ok, frames} = Rclex.Tf2.list_frames("main", "node")
      assert Enum.map(frames, & &1.child) == ["alpha", "zeta"]
    end

    test "preserves the native empty broadcaster" do
      :ok =
        Rclex.Tf2.set_transform(
          "main",
          stamped_transform("a", "b", 1, %{x: 0.0, y: 0.0, z: 0.0}),
          "",
          "node"
        )

      assert {:ok, [frame]} = Rclex.Tf2.list_frames("main", "node")
      assert frame.broadcaster == ""
    end

    test "returns an error for a missing buffer" do
      assert {:error, :buffer_not_found} = Rclex.Tf2.list_frames("absent", "node")
    end
  end
end
