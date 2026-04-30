defmodule Rclex.Tf2Test do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Rclex.Pkgs.BuiltinInterfaces.Msg.Time
  alias Rclex.Pkgs.GeometryMsgs.Msg.{Quaternion, Transform, TransformStamped, Vector3}
  alias Rclex.Pkgs.StdMsgs.Msg.Header

  @table :rclex_tf2_buffers

  setup do
    if :ets.whereis(@table) != :undefined do
      :ets.delete_all_objects(@table)
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
    test "creates, rejects duplicate, and destroys a buffer" do
      assert :ok = Rclex.tf2_buffer_new("main", "node")
      assert {:error, :buffer_already_exists} = Rclex.tf2_buffer_new("main", "node")

      assert :ok = Rclex.tf2_buffer_destroy("main", "node")
      assert {:error, :buffer_not_found} = Rclex.tf2_buffer_destroy("main", "node")
    end

    test "scopes buffers by namespace with default '/'" do
      assert :ok = Rclex.tf2_buffer_new("main", "node")
      assert :ok = Rclex.tf2_buffer_new("main", "node", namespace: "/robot1")

      assert :ok = Rclex.tf2_buffer_destroy("main", "node")
      assert :ok = Rclex.tf2_buffer_destroy("main", "node", namespace: "/robot1")
    end
  end

  describe "time-aware transform behavior" do
    setup do
      assert :ok = Rclex.tf2_buffer_new("main", "node")
      :ok
    end

    test "returns error for invalid transform payload" do
      assert {:error, :invalid_transform_stamped} =
               Rclex.tf2_set_transform("main", %{}, "authority", "node")
    end

    test "lookup latest with time_ns=0" do
      transform = stamped_transform("base_link", "camera_link", 10, %{x: 1.0, y: 2.0, z: 3.0})
      assert :ok = Rclex.tf2_set_transform("main", transform, "authority", "node")

      assert {:ok, found} =
               Rclex.tf2_lookup_transform(
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

    test "reports extrapolation into the future for explicit query time" do
      transform = stamped_transform("bar", "foo", 1, %{x: 2.0, y: 0.0, z: 0.0})
      assert :ok = Rclex.tf2_set_transform("main", transform, "authority", "node")

      assert {:error, :extrapolation_future} =
               Rclex.tf2_lookup_transform("main", "bar", "foo", 2_000_000_000, 0.0, "node")
    end

    test "reports extrapolation into the past for explicit query time" do
      transform = stamped_transform("bar", "foo", 2, %{x: 2.0, y: 0.0, z: 0.0})
      assert :ok = Rclex.tf2_set_transform("main", transform, "authority", "node")

      assert {:error, :extrapolation_past} =
               Rclex.tf2_lookup_transform("main", "bar", "foo", 1_000_000_000, 0.0, "node")
    end

    test "can_transform? returns boolean and optional debug tuple" do
      transform = stamped_transform("map", "odom", 1, %{x: 0.0, y: 0.0, z: 0.0})
      assert :ok = Rclex.tf2_set_transform("main", transform, "authority", "node")

      assert true == Rclex.tf2_can_transform?("main", "map", "odom", 0, 0.0, "node")

      assert {false, reason} =
               Rclex.tf2_can_transform?(
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
      assert :ok = Rclex.tf2_set_transform_static("main", transform, "authority", "node")

      assert {:ok, found} =
               Rclex.tf2_lookup_transform(
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
               Rclex.tf2_set_transform(
                 "main",
                 stamped_transform("map", "odom", 1, %{x: 0.0, y: 0.0, z: 0.0}),
                 "authority",
                 "node"
               )

      assert :ok =
               Rclex.tf2_set_transform(
                 "main",
                 stamped_transform("odom", "base_link", 3, %{x: 0.0, y: 0.0, z: 0.0}),
                 "authority",
                 "node"
               )

      assert {:ok, latest_ns} =
               Rclex.tf2_get_latest_common_time("main", "map", "base_link", "node")

      assert latest_ns == 1_000_000_000
    end

    test "clear removes all transforms" do
      assert :ok =
               Rclex.tf2_set_transform(
                 "main",
                 stamped_transform("map", "odom", 1, %{x: 0.0, y: 0.0, z: 0.0}),
                 "authority",
                 "node"
               )

      assert :ok =
               Rclex.tf2_set_transform(
                 "main",
                 stamped_transform("odom", "base_link", 3, %{x: 0.0, y: 0.0, z: 0.0}),
                 "authority",
                 "node"
               )

      assert {:ok, yaml_before} = Rclex.tf2_all_frames_as_yaml("main", "node")
      assert yaml_before =~ "map"
      assert yaml_before =~ "parent:"
      assert yaml_before =~ "broadcaster:"
      assert yaml_before =~ "most_recent_transform:"

      assert :ok = Rclex.tf2_clear("main", "node")

      assert {:ok, yaml_after} = Rclex.tf2_all_frames_as_yaml("main", "node")
      assert yaml_after == ""
      assert {:error, :lookup} = Rclex.tf2_lookup_transform("main", "map", "odom", 0, 0.0, "node")
    end
  end

  describe "example calculations" do
    setup do
      assert :ok = Rclex.tf2_buffer_new("main", "node")
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

      assert :ok = Rclex.tf2_set_transform("main", transform, "authority", "node")

      assert {:ok, found} =
               Rclex.tf2_lookup_transform(
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
               Rclex.tf2_set_transform(
                 "main",
                 stamped_transform("map", "odom", 10, %{x: 1.0, y: 0.0, z: 0.0}),
                 "authority",
                 "node"
               )

      assert :ok =
               Rclex.tf2_set_transform(
                 "main",
                 stamped_transform("odom", "base_link", 10, %{x: 0.0, y: 2.0, z: 0.0}),
                 "authority",
                 "node"
               )

      assert :ok =
               Rclex.tf2_set_transform(
                 "main",
                 stamped_transform("base_link", "camera_link", 10, %{x: 0.0, y: 0.0, z: 3.0}),
                 "authority",
                 "node"
               )

      assert {:ok, found} =
               Rclex.tf2_lookup_transform(
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

  describe "transport wiring guard rails" do
    setup do
      assert :ok = Rclex.tf2_buffer_new("main", "node")
      :ok
    end

    test "listener and broadcaster report missing tf message type module" do
      missing = Rclex.Pkgs.Tf2Msgs.Msg.MissingTFMessage

      assert {:error, {:tf_message_type_not_generated, _}} =
               Rclex.tf2_start_listener("main", "node", tf_message_type_module: missing)

      assert {:error, {:tf_message_type_not_generated, _}} =
               Rclex.tf2_start_broadcaster("node", tf_message_type_module: missing)
    end

    test "broadcast helpers report missing tf message type module" do
      missing = Rclex.Pkgs.Tf2Msgs.Msg.MissingTFMessage

      transform =
        stamped_transform("map", "base_link", 1, %{x: 0.0, y: 0.0, z: 0.0})

      assert {:error, {:tf_message_type_not_generated, _}} =
               Rclex.tf2_broadcast_dynamic(transform, "node", tf_message_type_module: missing)

      assert {:error, {:tf_message_type_not_generated, _}} =
               Rclex.tf2_broadcast_static(transform, "node", tf_message_type_module: missing)
    end
  end

  describe "transport wiring end-to-end" do
    setup do
      :ok = Application.ensure_started(:rclex)

      name = "tf_wire_node"
      namespace = "/"

      assert :ok = Rclex.start_node(name, namespace: namespace)
      assert :ok = Rclex.tf2_buffer_new("main", name, namespace: namespace)

      on_exit(fn ->
        _ =
          capture_log(fn ->
            _ = Rclex.tf2_stop_listener("main", name, namespace: namespace)
            _ = Rclex.tf2_stop_broadcaster(name, namespace: namespace)
            _ = Rclex.tf2_buffer_destroy("main", name, namespace: namespace)
            _ = Rclex.stop_node(name, namespace: namespace)
          end)
      end)

      %{name: name, namespace: namespace}
    end

    test "broadcast_dynamic is ingested by listener and available for lookup", %{
      name: name,
      namespace: namespace
    } do
      assert :ok = Rclex.tf2_start_listener("main", name, namespace: namespace)
      assert :ok = Rclex.tf2_start_broadcaster(name, namespace: namespace)

      ts = %TransformStamped{
        header: %Header{frame_id: "map", stamp: %Time{sec: 42, nanosec: 0}},
        child_frame_id: "base_link",
        transform: %Transform{
          translation: %Vector3{x: 1.0, y: 2.0, z: 3.0},
          rotation: %Quaternion{w: 1.0, x: 0.0, y: 0.0, z: 0.0}
        }
      }

      assert :ok = Rclex.tf2_broadcast_dynamic(ts, name, namespace: namespace)

      assert {:ok, found} =
               Rclex.tf2_lookup_transform(
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

  describe "operations on missing buffer" do
    test "returns :buffer_not_found for clear/lookup/all_frames/get_latest_common_time/can_transform?/set_transform" do
      assert {:error, :buffer_not_found} = Rclex.tf2_clear("absent", "node")
      assert {:error, :buffer_not_found} = Rclex.tf2_all_frames_as_yaml("absent", "node")

      assert {:error, :buffer_not_found} =
               Rclex.tf2_lookup_transform("absent", "a", "b", 0, 0.0, "node")

      assert {:error, :buffer_not_found} =
               Rclex.tf2_get_latest_common_time("absent", "a", "b", "node")

      assert {:error, :buffer_not_found} =
               Rclex.tf2_can_transform?("absent", "a", "b", 0, 0.0, "node")

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
               Rclex.tf2_set_transform("absent", transform, "auth", "node")
    end
  end

  describe "validation errors" do
    setup do
      assert :ok = Rclex.tf2_buffer_new("main", "node")
      :ok
    end

    test "invalid frame ids when looking up" do
      transform = stamped_transform("a", "b", 1, %{x: 0.0, y: 0.0, z: 0.0})
      assert :ok = Rclex.tf2_set_transform("main", transform, "auth", "node")

      assert {:error, :invalid_target_frame} =
               Rclex.tf2_lookup_transform("main", "", "b", 0, 0.0, "node")

      assert {:error, :invalid_source_frame} =
               Rclex.tf2_lookup_transform("main", "a", "  ", 0, 0.0, "node")

      assert {:error, :invalid_target_frame} =
               Rclex.tf2_get_latest_common_time("main", "", "b", "node")
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
               Rclex.tf2_set_transform("main", bad_translation, "auth", "node")

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
               Rclex.tf2_set_transform("main", bad_rotation, "auth", "node")
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
               Rclex.tf2_set_transform("main", bad_stamp, "auth", "node")
    end

    test "lookup with unknown frame returns :lookup" do
      transform = stamped_transform("a", "b", 1, %{x: 0.0, y: 0.0, z: 0.0})
      assert :ok = Rclex.tf2_set_transform("main", transform, "auth", "node")

      assert {:error, :lookup} =
               Rclex.tf2_lookup_transform("main", "a", "z", 0, 0.0, "node")
    end

    test "can_transform? debug tuple succeeds with empty reason" do
      transform = stamped_transform("a", "b", 1, %{x: 0.0, y: 0.0, z: 0.0})
      assert :ok = Rclex.tf2_set_transform("main", transform, "auth", "node")

      assert {true, ""} =
               Rclex.tf2_can_transform?("main", "a", "b", 0, 0.0, "node",
                 return_debug_tuple: true
               )
    end
  end

  describe "interpolation and extrapolation" do
    setup do
      assert :ok = Rclex.tf2_buffer_new("main", "node")

      :ok =
        Rclex.tf2_set_transform(
          "main",
          stamped_transform("a", "b", 1, %{x: 0.0, y: 0.0, z: 0.0}),
          "auth",
          "node"
        )

      :ok =
        Rclex.tf2_set_transform(
          "main",
          stamped_transform("a", "b", 3, %{x: 2.0, y: 0.0, z: 0.0}),
          "auth",
          "node"
        )

      :ok
    end

    test "interpolates between two stamps" do
      assert {:ok, found} =
               Rclex.tf2_lookup_transform("main", "a", "b", 2_000_000_000, 0.0, "node")

      assert_in_delta found.transform.translation.x, 1.0, 1.0e-6
      assert found.header.stamp.sec == 2
    end

    test "exact-stamp lookup returns that sample" do
      assert {:ok, found} =
               Rclex.tf2_lookup_transform("main", "a", "b", 1_000_000_000, 0.0, "node")

      assert_in_delta found.transform.translation.x, 0.0, 1.0e-6
    end

    test "extrapolation in past below first sample" do
      assert {:error, :extrapolation_past} =
               Rclex.tf2_lookup_transform("main", "a", "b", 500_000_000, 0.0, "node")
    end

    test "extrapolation in future above last sample" do
      assert {:error, :extrapolation_future} =
               Rclex.tf2_lookup_transform("main", "a", "b", 5_000_000_000, 0.0, "node")
    end
  end

  describe "slerp interpolation" do
    setup do
      assert :ok = Rclex.tf2_buffer_new("main", "node")
      :ok
    end

    test "interpolates rotation halfway between 0 and 90 deg yaw" do
      half_pi = :math.pi() / 2.0
      half_angle = half_pi / 2.0

      :ok =
        Rclex.tf2_set_transform(
          "main",
          stamped_transform("a", "b", 1, %{x: 0.0, y: 0.0, z: 0.0},
            %{w: 1.0, x: 0.0, y: 0.0, z: 0.0}),
          "auth",
          "node"
        )

      :ok =
        Rclex.tf2_set_transform(
          "main",
          stamped_transform("a", "b", 3, %{x: 0.0, y: 0.0, z: 0.0},
            %{w: :math.cos(half_angle), x: 0.0, y: 0.0, z: :math.sin(half_angle)}),
          "auth",
          "node"
        )

      assert {:ok, found} =
               Rclex.tf2_lookup_transform("main", "a", "b", 2_000_000_000, 0.0, "node")

      yaw = quaternion_to_yaw(found.transform.rotation)
      # Halfway should be about pi/4
      assert_in_delta yaw, half_pi / 2.0, 1.0e-3
    end
  end

  describe "broadcast helpers without active publisher" do
    test "broadcast_dynamic with default tf message type but no publisher returns error" do
      transform = stamped_transform("a", "b", 1, %{x: 0.0, y: 0.0, z: 0.0})

      result = Rclex.tf2_broadcast_dynamic(transform, "no_such_node")
      assert match?({:error, _}, result)
    end

    test "broadcast_static with list works through normalization" do
      transform = stamped_transform("a", "b", 1, %{x: 0.0, y: 0.0, z: 0.0})

      result = Rclex.tf2_broadcast_static([transform], "no_such_node")
      assert match?({:error, _}, result)
    end
  end

  describe "namespace scoping" do
    test "lookup is isolated per namespace" do
      :ok = Rclex.tf2_buffer_new("main", "node", namespace: "/ns_a")
      :ok = Rclex.tf2_buffer_new("main", "node", namespace: "/ns_b")

      :ok =
        Rclex.tf2_set_transform(
          "main",
          stamped_transform("a", "b", 1, %{x: 1.0, y: 0.0, z: 0.0}),
          "auth",
          "node",
          namespace: "/ns_a"
        )

      assert {:error, :lookup} =
               Rclex.tf2_lookup_transform(
                 "main",
                 "a",
                 "b",
                 0,
                 0.0,
                 "node",
                 namespace: "/ns_b"
               )

      assert {:ok, found} =
               Rclex.tf2_lookup_transform(
                 "main",
                 "a",
                 "b",
                 0,
                 0.0,
                 "node",
                 namespace: "/ns_a"
               )

      assert_in_delta found.transform.translation.x, 1.0, 1.0e-6

      _ = Rclex.tf2_buffer_destroy("main", "node", namespace: "/ns_a")
      _ = Rclex.tf2_buffer_destroy("main", "node", namespace: "/ns_b")
    end
  end

  describe "transitive transform via reverse edges" do
    setup do
      assert :ok = Rclex.tf2_buffer_new("main", "node")
      :ok
    end

    test "lookups walk reverse edges through inverted transforms" do
      :ok =
        Rclex.tf2_set_transform(
          "main",
          stamped_transform("map", "odom", 10, %{x: 1.0, y: 0.0, z: 0.0}),
          "auth",
          "node"
        )

      :ok =
        Rclex.tf2_set_transform(
          "main",
          stamped_transform("base_link", "odom", 10, %{x: 0.0, y: 5.0, z: 0.0}),
          "auth",
          "node"
        )

      assert {:ok, found} =
               Rclex.tf2_lookup_transform(
                 "main",
                 "map",
                 "base_link",
                 10_000_000_000,
                 0.0,
                 "node"
               )

      # Going map -> odom (+1, 0) and inverse of base_link -> odom (0, -5),
      # so map -> base_link should be (+1, -5, 0).
      assert_in_delta found.transform.translation.x, 1.0, 1.0e-6
      assert_in_delta found.transform.translation.y, -5.0, 1.0e-6
    end
  end

  describe "extra branches" do
    setup do
      assert :ok = Rclex.tf2_buffer_new("main", "node")
      :ok
    end

    test "buffer_destroy on existing buffer also clears state" do
      :ok =
        Rclex.tf2_set_transform(
          "main",
          stamped_transform("a", "b", 1, %{x: 0.0, y: 0.0, z: 0.0}),
          "auth",
          "node"
        )

      :ok = Rclex.tf2_buffer_destroy("main", "node")
      :ok = Rclex.tf2_buffer_new("main", "node")

      assert {:ok, ""} = Rclex.tf2_all_frames_as_yaml("main", "node")
    end

    test "set_transform_static with cache_time_sec=0 keeps only latest" do
      :ok = Rclex.tf2_buffer_destroy("main", "node")
      :ok = Rclex.tf2_buffer_new("main", "node", cache_time_sec: 0.0)

      :ok =
        Rclex.tf2_set_transform(
          "main",
          stamped_transform("a", "b", 1, %{x: 0.0, y: 0.0, z: 0.0}),
          "auth",
          "node"
        )

      :ok =
        Rclex.tf2_set_transform(
          "main",
          stamped_transform("a", "b", 5, %{x: 1.0, y: 0.0, z: 0.0}),
          "auth",
          "node"
        )

      # With cache_time_ns == 0, only the latest is kept. So lookup at
      # latest stamp returns the latest transform.
      assert {:ok, found} =
               Rclex.tf2_lookup_transform("main", "a", "b", 5_000_000_000, 0.0, "node")

      assert_in_delta found.transform.translation.x, 1.0, 1.0e-6
    end

    test "duplicate-stamp samples are deduped" do
      :ok =
        Rclex.tf2_set_transform(
          "main",
          stamped_transform("a", "b", 1, %{x: 1.0, y: 0.0, z: 0.0}),
          "auth",
          "node"
        )

      :ok =
        Rclex.tf2_set_transform(
          "main",
          stamped_transform("a", "b", 1, %{x: 9.0, y: 0.0, z: 0.0}),
          "auth",
          "node"
        )

      assert {:ok, found} =
               Rclex.tf2_lookup_transform("main", "a", "b", 1_000_000_000, 0.0, "node")

      assert_in_delta found.transform.translation.x, 9.0, 1.0e-6
    end

    test "yaml output contains broadcaster fallback when authority is empty" do
      :ok =
        Rclex.tf2_set_transform(
          "main",
          stamped_transform("a", "b", 1, %{x: 0.0, y: 0.0, z: 0.0}),
          "",
          "node"
        )

      assert {:ok, yaml} = Rclex.tf2_all_frames_as_yaml("main", "node")
      assert yaml =~ "broadcaster: unknown"
    end
  end
end