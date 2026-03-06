defmodule Rclex.Tf2Test do
  use ExUnit.Case, async: false

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

  defp stamped_transform(parent, child, sec, translation, rotation \\ %{w: 1.0, x: 0.0, y: 0.0, z: 0.0}) do
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
        _ = Rclex.tf2_stop_listener("main", name, namespace: namespace)
        _ = Rclex.tf2_stop_broadcaster(name, namespace: namespace)
        _ = Rclex.tf2_buffer_destroy("main", name, namespace: namespace)
        _ = Rclex.stop_node(name, namespace: namespace)
      end)

      %{name: name, namespace: namespace}
    end

    test "broadcast_dynamic is ingested by listener and available for lookup", %{name: name, namespace: namespace} do
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
end
