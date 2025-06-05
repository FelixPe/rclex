defmodule Rclex.Generators.MsgCTest do
  use ExUnit.Case
  doctest Rclex.Generators.MsgC

  with ros_distro <- System.get_env("ROS_DISTRO"),
       true <- File.exists?("/opt/ros/#{ros_distro}") do
    @ros_share_path ["/opt/ros/#{ros_distro}/share"]
  else
    _ ->
      @moduletag :skip
  end

  alias Mix.Tasks.Rclex.Gen.Msgs
  alias Rclex.Generators.MsgC
  alias Rclex.Generators.Util

  for ros2_message_type <- [
        "action_msgs/msg/GoalInfo",
        "sensor_msgs/msg/PointCloud",
        "std_msgs/msg/Empty",
        "std_msgs/msg/String",
        "std_msgs/msg/MultiArrayDimension",
        "std_msgs/msg/MultiArrayLayout",
        "std_msgs/msg/UInt32MultiArray",
        "geometry_msgs/msg/Vector3",
        "geometry_msgs/msg/Twist",
        "std_srvs/srv/SetBool_Request",
        "std_srvs/srv/SetBool_Response",
        "rcl_interfaces/msg/ParameterDescriptor",
        "rcl_interfaces/srv/GetParameterTypes_Request",
        "rcl_interfaces/srv/GetParameterTypes_Response",
        "tf2_msgs/action/LookupTransform_FeedbackMessage",
        "tf2_msgs/action/LookupTransform_Feedback",
        "tf2_msgs/action/LookupTransform_Goal",
        "tf2_msgs/action/LookupTransform_Result",
        "tf2_msgs/action/LookupTransform_GetResult_Request",
        "tf2_msgs/action/LookupTransform_GetResult_Response",
        "tf2_msgs/action/LookupTransform_SendGoal_Request",
        "tf2_msgs/action/LookupTransform_SendGoal_Response"
      ] do
    test "generate/2 #{ros2_message_type}" do
      ros2_message_type = unquote(ros2_message_type)
      ros2_message_type_map = Msgs.get_ros2_message_type_map(ros2_message_type, @ros_share_path)

      [interfaces, msg, type] = String.split(ros2_message_type, "/")
      type_path = Enum.join([interfaces, msg, Util.to_down_snake(type)], "/")

      assert MsgC.generate(ros2_message_type, ros2_message_type_map) ==
               File.read!(Path.join(File.cwd!(), "test/expected_files/#{type_path}.c"))
    end
  end

  for ros2_message_type <- [
        "sensor_msgs/msg/PointCloud",
        "std_msgs/msg/Empty",
        "std_msgs/msg/String",
        "std_msgs/msg/MultiArrayDimension",
        "std_msgs/msg/MultiArrayLayout",
        "std_msgs/msg/UInt32MultiArray",
        "geometry_msgs/msg/Vector3",
        "geometry_msgs/msg/Twist",
        "std_srvs/srv/SetBool_Request",
        "std_srvs/srv/SetBool_Response",
        "rcl_interfaces/msg/ParameterDescriptor",
        "rcl_interfaces/srv/GetParameterTypes_Request",
        "rcl_interfaces/srv/GetParameterTypes_Response"
      ] do
    test "get_fun_fragments/2 #{ros2_message_type}" do
      ros2_message_type = unquote(ros2_message_type)
      ros2_message_type_map = Msgs.get_ros2_message_type_map(ros2_message_type, @ros_share_path)

      [interfaces, msg, type] = String.split(ros2_message_type, "/")
      type_path = Enum.join([interfaces, msg, Util.to_down_snake(type)], "/")

      assert MsgC.get_fun_fragments(ros2_message_type, ros2_message_type_map) ==
               File.read!(Path.join(File.cwd!(), "test/expected_files/#{type_path}_get_fun.txt"))
               |> String.replace_suffix("\n", "")
    end
  end

  for ros2_message_type <- [
        "sensor_msgs/msg/PointCloud",
        "std_msgs/msg/Empty",
        "std_msgs/msg/String",
        "std_msgs/msg/MultiArrayDimension",
        "std_msgs/msg/MultiArrayLayout",
        "std_msgs/msg/UInt32MultiArray",
        "geometry_msgs/msg/Vector3",
        "geometry_msgs/msg/Twist",
        "std_srvs/srv/SetBool_Request",
        "std_srvs/srv/SetBool_Response",
        "rcl_interfaces/msg/ParameterDescriptor",
        "rcl_interfaces/srv/GetParameterTypes_Request",
        "rcl_interfaces/srv/GetParameterTypes_Response"
      ] do
    test "set_fun_fragments/2 #{ros2_message_type}" do
      ros2_message_type = unquote(ros2_message_type)
      ros2_message_type_map = Msgs.get_ros2_message_type_map(ros2_message_type, @ros_share_path)

      [interfaces, msg, type] = String.split(ros2_message_type, "/")
      type_path = Enum.join([interfaces, msg, Util.to_down_snake(type)], "/")

      assert MsgC.set_fun_fragments(ros2_message_type, ros2_message_type_map) ==
               File.read!(Path.join(File.cwd!(), "test/expected_files/#{type_path}_set_fun.txt"))
               |> String.replace_suffix("\n", "")
    end
  end

  describe "utility functions" do
    test "to_header_name/1 extracts type name correctly" do
      assert MsgC.to_header_name("std_msgs/msg/String") == "string"
      assert MsgC.to_header_name("geometry_msgs/msg/Vector3") == "vector3"
      assert MsgC.to_header_name("std_msgs/msg/UInt32MultiArray") == "u_int32_multi_array"

      assert MsgC.to_header_name("tf2_msgs/action/LookupTransform_Goal") ==
               "lookup_transform__goal"
    end

    test "to_header_prefix/1 generates correct header prefixes" do
      assert MsgC.to_header_prefix("std_msgs/msg/String") == "std_msgs/msg/detail/string"

      assert MsgC.to_header_prefix("geometry_msgs/msg/Vector3") ==
               "geometry_msgs/msg/detail/vector3"

      assert MsgC.to_header_prefix("std_srvs/srv/SetBool_Request") ==
               "std_srvs/srv/detail/set_bool"

      assert MsgC.to_header_prefix("tf2_msgs/action/LookupTransform_Goal") ==
               "tf2_msgs/action/detail/lookup_transform"
    end

    test "rosidl_get_msg_type_support/1 generates correct macros" do
      assert MsgC.rosidl_get_msg_type_support("std_msgs/msg/String") ==
               "ROSIDL_GET_MSG_TYPE_SUPPORT(std_msgs, msg, String)"

      assert MsgC.rosidl_get_msg_type_support("geometry_msgs/msg/Vector3") ==
               "ROSIDL_GET_MSG_TYPE_SUPPORT(geometry_msgs, msg, Vector3)"

      assert MsgC.rosidl_get_msg_type_support("tf2_msgs/action/LookupTransform_Goal") ==
               "ROSIDL_GET_MSG_TYPE_SUPPORT(tf2_msgs, action, LookupTransform_Goal)"
    end

    test "to_deps_header_prefix_list/2 handles empty dependencies" do
      ros2_message_type_map = %{
        {:msg_type, "std_msgs/msg/Empty"} => []
      }

      result = MsgC.to_deps_header_prefix_list("std_msgs/msg/Empty", ros2_message_type_map)
      assert result == []
    end

    test "to_deps_header_prefix_list/2 generates dependencies for complex types" do
      ros2_message_type_map =
        Msgs.get_ros2_message_type_map("geometry_msgs/msg/Twist", @ros_share_path)

      result = MsgC.to_deps_header_prefix_list("geometry_msgs/msg/Twist", ros2_message_type_map)
      assert "geometry_msgs/msg/detail/vector3" in result
    end
  end

  describe "builtin type handling" do
    test "enif_get handles all builtin types correctly" do
      acc = %MsgC.Acc{vars: ["test"], mbrs: ["data"], terms: ["term"]}

      # Test string type
      result = MsgC.enif_get({:builtin_type, "string"}, acc, %{})
      assert result =~ "ErlNifBinary test_binary"
      assert result =~ "enif_inspect_binary"
      assert result =~ "rosidl_runtime_c__String__assignn"

      # Test boolean type
      result = MsgC.enif_get({:builtin_type, "bool"}, acc, %{})
      assert result =~ "enif_get_atom_length"
      assert result =~ "strncmp"
      assert result =~ "true"

      # Test integer types
      result = MsgC.enif_get({:builtin_type, "int32"}, acc, %{})
      assert result =~ "enif_get_int"

      result = MsgC.enif_get({:builtin_type, "uint32"}, acc, %{})
      assert result =~ "enif_get_uint"

      result = MsgC.enif_get({:builtin_type, "int64"}, acc, %{})
      assert result =~ "enif_get_int64"

      result = MsgC.enif_get({:builtin_type, "uint64"}, acc, %{})
      assert result =~ "enif_get_uint64"

      # Test float types
      result = MsgC.enif_get({:builtin_type, "float32"}, acc, %{})
      assert result =~ "enif_get_double"
      assert result =~ "(float)"

      result = MsgC.enif_get({:builtin_type, "float64"}, acc, %{})
      assert result =~ "enif_get_double"

      # Test byte type
      result = MsgC.enif_get({:builtin_type, "byte"}, acc, %{})
      assert result =~ "enif_get_uint"
      assert result =~ "(uint8_t)"
    end

    test "enif_make handles all builtin types correctly" do
      acc = %MsgC.Acc{vars: ["test"], mbrs: ["data"], terms: ["term"]}

      # Test string type
      {result, _acc} = MsgC.enif_make({:builtin_type, "string"}, acc, %{})
      assert result =~ "enif_make_binary_wrapper"

      # Test boolean type
      {result, _acc} = MsgC.enif_make({:builtin_type, "bool"}, acc, %{})
      assert result =~ "enif_make_atom"
      assert result =~ "true"
      assert result =~ "false"

      # Test integer types
      {result, _acc} = MsgC.enif_make({:builtin_type, "int32"}, acc, %{})
      assert result =~ "enif_make_int"

      {result, _acc} = MsgC.enif_make({:builtin_type, "uint32"}, acc, %{})
      assert result =~ "enif_make_uint"

      {result, _acc} = MsgC.enif_make({:builtin_type, "int64"}, acc, %{})
      assert result =~ "enif_make_int64"

      {result, _acc} = MsgC.enif_make({:builtin_type, "uint64"}, acc, %{})
      assert result =~ "enif_make_uint64"

      # Test float types
      {result, _acc} = MsgC.enif_make({:builtin_type, "float32"}, acc, %{})
      assert result =~ "enif_make_double"

      {result, _acc} = MsgC.enif_make({:builtin_type, "float64"}, acc, %{})
      assert result =~ "enif_make_double"
    end
  end

  describe "array type handling" do
    test "handles builtin type arrays correctly" do
      ros2_message_type_map =
        Msgs.get_ros2_message_type_map("std_msgs/msg/UInt8MultiArray", @ros_share_path)

      acc = %MsgC.Acc{vars: ["test"], mbrs: ["data"], terms: ["term"]}

      result = MsgC.enif_get({:builtin_type_array, "uint8[]"}, acc, ros2_message_type_map)
      assert result =~ "test_length = test_bin.size"
      assert result =~ "rosidl_runtime_c__uint8__Sequence"
    end

    test "handles message type arrays correctly" do
      ros2_message_type_map =
        Msgs.get_ros2_message_type_map("std_msgs/msg/MultiArrayLayout", @ros_share_path)

      acc = %MsgC.Acc{vars: ["test"], mbrs: ["dim"], terms: ["term"]}

      result =
        MsgC.enif_get(
          {:msg_type_array, "std_msgs/msg/MultiArrayDimension[]"},
          acc,
          ros2_message_type_map
        )

      assert result =~ "enif_get_list_length"
      assert result =~ "std_msgs__msg__MultiArrayDimension__Sequence"
    end

    test "handles static arrays correctly" do
      acc = %MsgC.Acc{vars: ["test"], mbrs: ["data"], terms: ["term"]}

      result = MsgC.enif_get({:builtin_type_array, "uint8[16]"}, acc, %{})
      assert result =~ "enif_inspect_binary(env, term, &test_bin)"
      assert result =~ "16"
    end
  end

  describe "error handling" do
    test "set_fun_fragments handles empty types" do
      ros2_message_type_map = %{
        {:msg_type, "std_msgs/msg/Empty"} => []
      }

      result = MsgC.set_fun_fragments("std_msgs/msg/Empty", ros2_message_type_map)
      assert result == ""
    end

    test "get_fun_fragments handles empty types" do
      ros2_message_type_map = %{
        {:msg_type, "std_msgs/msg/Empty"} => []
      }

      result = MsgC.get_fun_fragments("std_msgs/msg/Empty", ros2_message_type_map)
      assert result =~ "enif_make_tuple(env, 0)"
    end
  end

  describe "complex type scenarios" do
    test "handles nested message types correctly" do
      ros2_message_type_map =
        Msgs.get_ros2_message_type_map("geometry_msgs/msg/Twist", @ros_share_path)

      result = MsgC.set_fun_fragments("geometry_msgs/msg/Twist", ros2_message_type_map)
      assert result =~ "linear_arity"
      assert result =~ "angular_arity"
      assert result =~ "enif_get_tuple"
    end

    test "handles service request/response types" do
      ros2_message_type_map =
        Msgs.get_ros2_message_type_map("std_srvs/srv/SetBool_Request", @ros_share_path)

      result = MsgC.generate("std_srvs/srv/SetBool_Request", ros2_message_type_map)
      assert result =~ "nif_std_srvs_srv_set_bool__request"
      assert result =~ "std_srvs__srv__SetBool_Request"
    end

    test "handles action types correctly" do
      ros2_message_type_map =
        Msgs.get_ros2_message_type_map("tf2_msgs/action/LookupTransform_Goal", @ros_share_path)

      result = MsgC.generate("tf2_msgs/action/LookupTransform_Goal", ros2_message_type_map)
      assert result =~ "nif_tf2_msgs_action_lookup_transform__goal"
      assert result =~ "tf2_msgs__action__LookupTransform_Goal"
    end
  end
end
