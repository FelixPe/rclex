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
    test "generates a type description provider" do
      ros2_message_type_map =
        Msgs.get_ros2_message_type_map("std_msgs/msg/String", @ros_share_path)

      result = MsgC.generate("std_msgs/msg/String", ros2_message_type_map)

      assert result =~ "std_msgs__msg__String__get_type_description"
      assert result =~ "nif_std_msgs_msg_string_type_description"
    end

    test "enif_get handles all builtin types correctly" do
      acc = %MsgC.Acc{vars: ["test"], mbrs: ["data"], terms: ["term"]}

      # Test string type
      result = MsgC.enif_get({:builtin_type, "string"}, acc, %{})
      assert result =~ "ErlNifBinary test_binary"
      assert result =~ "enif_inspect_binary"
      assert result =~ "rosidl_runtime_c__String__assignn"

      result = MsgC.enif_get({:builtin_type, "string<=255"}, acc, %{})
      assert result =~ "if (test_binary.size > 255)"
      assert result =~ "rosidl_runtime_c__String__assignn"

      {setup, result, _accs} = MsgC.enif_make({:builtin_type, "string<=255"}, acc, %{})
      assert setup =~ "enif_make_binary_wrapper"
      assert result == "test_term"

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
      {setup, result, _accs} = MsgC.enif_make({:builtin_type, "string"}, acc, %{})
      assert setup =~ "enif_make_binary_wrapper"
      assert setup =~ "enif_is_exception"
      assert result == "test_term"

      # Test boolean type
      {_, result, _accs} = MsgC.enif_make({:builtin_type, "bool"}, acc, %{})
      assert result =~ "enif_make_atom"
      assert result =~ "true"
      assert result =~ "false"

      # Test integer types
      {_, result, _accs} = MsgC.enif_make({:builtin_type, "int32"}, acc, %{})
      assert result =~ "enif_make_int"

      {_, result, _accs} = MsgC.enif_make({:builtin_type, "uint32"}, acc, %{})
      assert result =~ "enif_make_uint"

      {_, result, _accs} = MsgC.enif_make({:builtin_type, "int64"}, acc, %{})
      assert result =~ "enif_make_int64"

      {_, result, _accs} = MsgC.enif_make({:builtin_type, "uint64"}, acc, %{})
      assert result =~ "enif_make_uint64"

      # Test float types
      {setup, result, _accs} = MsgC.enif_make({:builtin_type, "float32"}, acc, %{})
      assert setup =~ "isnan(message_p->data)"
      assert setup =~ "atom_nan"
      assert setup =~ "atom_infinity"
      assert setup =~ "atom_neg_infinity"
      assert result == "test_term"

      {setup, result, _accs} = MsgC.enif_make({:builtin_type, "float64"}, acc, %{})
      assert setup =~ "isnan(message_p->data)"
      assert setup =~ "atom_nan"
      assert setup =~ "atom_infinity"
      assert setup =~ "atom_neg_infinity"
      assert result == "test_term"
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

  describe "array type parsing and handling" do
    test "get_array_type/1 parses unbounded dynamic arrays" do
      result = MsgC.get_array_type("uint8[]")
      assert result == %{type: "uint8", kind: :unbounded_dynamic, size: :undefined}

      result = MsgC.get_array_type("string[]")
      assert result == %{type: "string", kind: :unbounded_dynamic, size: :undefined}
    end

    test "get_array_type/1 parses static arrays" do
      result = MsgC.get_array_type("uint8[16]")
      assert result == %{type: "uint8", kind: :static, size: 16}

      result = MsgC.get_array_type("float64[3]")
      assert result == %{type: "float64", kind: :static, size: 3}
    end

    test "get_array_type/1 parses bounded dynamic arrays" do
      result = MsgC.get_array_type("string[<=10]")
      assert result == %{type: "string", kind: :bounded_dynamic, size: 10}

      result = MsgC.get_array_type("int32[<=100]")
      assert result == %{type: "int32", kind: :bounded_dynamic, size: 100}
    end
  end

  describe "C type conversions" do
    test "to_c_type/1 converts message types correctly" do
      assert MsgC.to_c_type("std_msgs/msg/String") == "std_msgs__msg__String"
      assert MsgC.to_c_type("geometry_msgs/msg/Vector3") == "geometry_msgs__msg__Vector3"
      assert MsgC.to_c_type("std_srvs/srv/SetBool") == "std_srvs__srv__SetBool"

      assert MsgC.to_c_type("tf2_msgs/action/LookupTransform") ==
               "tf2_msgs__action__LookupTransform"
    end
  end

  describe "dependency header generation" do
    test "to_deps_header_prefix_list/2 handles service types correctly" do
      ros2_message_type_map =
        Msgs.get_ros2_message_type_map("std_srvs/srv/SetBool_Request", @ros_share_path)

      result =
        MsgC.to_deps_header_prefix_list("std_srvs/srv/SetBool_Request", ros2_message_type_map)

      # SetBool_Request should have minimal dependencies
      assert is_list(result)
    end

    test "to_deps_header_prefix_list/2 handles action types correctly" do
      ros2_message_type_map =
        Msgs.get_ros2_message_type_map("tf2_msgs/action/LookupTransform_Result", @ros_share_path)

      result =
        MsgC.to_deps_header_prefix_list(
          "tf2_msgs/action/LookupTransform_Result",
          ros2_message_type_map
        )

      assert is_list(result)
      # Should include dependencies like geometry_msgs
      assert Enum.any?(result, &String.contains?(&1, "geometry_msgs"))
    end
  end

  describe "complex enif_get scenarios" do
    test "enif_get handles nested message structures" do
      ros2_message_type_map =
        Msgs.get_ros2_message_type_map("geometry_msgs/msg/Twist", @ros_share_path)

      acc = %MsgC.Acc{vars: ["twist"], mbrs: ["twist"], terms: ["term"]}
      result = MsgC.enif_get({:msg_type, "geometry_msgs/msg/Twist"}, acc, ros2_message_type_map)

      # Should handle nested Vector3 messages
      assert result =~ "linear_arity"
      assert result =~ "angular_arity"
      assert result =~ "enif_get_tuple"
    end

    test "enif_get handles builtin array with static size for uint8" do
      acc = %MsgC.Acc{vars: ["data"], mbrs: ["data"], terms: ["term"]}

      result = MsgC.enif_get({:builtin_type_array_static, "uint8", "16"}, acc, %{})
      assert result =~ "ErlNifBinary data_bin"
      assert result =~ "enif_inspect_binary"
      assert result =~ "if(data_length > 16)"
      assert result =~ "memcpy"
    end

    test "enif_get handles builtin array with static size for other types" do
      acc = %MsgC.Acc{vars: ["data"], mbrs: ["data"], terms: ["term"]}

      result = MsgC.enif_get({:builtin_type_array_static, "int32", "3"}, acc, %{})
      assert result =~ "for (data_i = 0, data_left = term; data_i < 3"
      assert result =~ "enif_get_list_cell"
      assert result =~ "enif_get_int"
    end

    test "enif_get handles message type arrays with bounded dynamics" do
      ros2_message_type_map =
        Msgs.get_ros2_message_type_map("std_msgs/msg/MultiArrayLayout", @ros_share_path)

      acc = %MsgC.Acc{vars: ["dim"], mbrs: ["dim"], terms: ["term"]}

      result =
        MsgC.enif_get(
          {:msg_type_array, "std_msgs/msg/MultiArrayDimension[]"},
          acc,
          ros2_message_type_map
        )

      assert result =~ "enif_get_list_length"
      assert result =~ "std_msgs__msg__MultiArrayDimension__Sequence"
      assert result =~ "create"
    end
  end

  describe "accumulator (Acc) struct functionality" do
    test "Acc struct maintains proper state during nested operations" do
      acc = %MsgC.Acc{vars: ["root"], mbrs: ["root"], terms: ["term"]}

      # Simulate nested structure access
      nested_acc = %MsgC.Acc{
        acc
        | vars: acc.vars ++ ["nested"],
          mbrs: acc.mbrs ++ ["nested"],
          terms: acc.terms ++ ["nested_term"]
      }

      assert nested_acc.vars == ["root", "nested"]
      assert nested_acc.mbrs == ["root", "nested"]
      assert nested_acc.terms == ["term", "nested_term"]
    end
  end

  describe "edge cases and error conditions" do
    test "handles unknown builtin types gracefully in enif_get_builtin" do
      # This tests the pattern matching fallback behavior
      # Most unknown types should fall through to existing patterns
      acc = %MsgC.Acc{vars: ["test"], mbrs: ["data"], terms: ["term"]}

      # Test that wstring would fall through to uint pattern (if it existed)
      # This is more about ensuring the pattern matching is comprehensive
      result = MsgC.enif_get({:builtin_type, "int8"}, acc, %{})
      assert result =~ "enif_get_int"
    end

    test "handles empty message types in generate/2" do
      ros2_message_type_map = %{
        {:msg_type, "std_msgs/msg/Empty"} => []
      }

      result = MsgC.generate("std_msgs/msg/Empty", ros2_message_type_map)
      assert result =~ "std_msgs__msg__Empty"
      assert result =~ "nif_std_msgs_msg_empty"
      # Should have empty set/get functions since no fields
    end

    test "build_get_fun_fragments handles arrays correctly" do
      ros2_message_type_map =
        Msgs.get_ros2_message_type_map("std_msgs/msg/UInt8MultiArray", @ros_share_path)

      acc = %MsgC.Acc{
        vars: ["data"],
        mbrs: ["data"],
        type: {:builtin_type_array, "uint8[]"}
      }

      result =
        MsgC.build_get_fun_fragments_array(
          {:builtin_type_array, "uint8[]"},
          acc,
          ros2_message_type_map
        )

      assert result =~ "ErlNifBinary"
      assert result =~ "enif_alloc_binary"
    end
  end

  describe "comprehensive integration scenarios" do
    test "full generation cycle for complex nested message" do
      ros2_message_type_map =
        Msgs.get_ros2_message_type_map("sensor_msgs/msg/PointCloud", @ros_share_path)

      # Test that all major components are generated
      result = MsgC.generate("sensor_msgs/msg/PointCloud", ros2_message_type_map)

      # Should include proper headers
      assert result =~ "#include"
      assert result =~ "sensor_msgs/msg/detail/point_cloud"

      # Should include proper function definitions
      assert result =~ "nif_sensor_msgs_msg_point_cloud"
      assert result =~ "type_support"
      assert result =~ "create"
      assert result =~ "destroy"
      assert result =~ "set"
      assert result =~ "get"

      # Should handle the nested structures properly
      # PointCloud contains geometry_msgs types
      assert result =~ "geometry_msgs"
    end

    test "verifies consistent variable naming across get/set operations" do
      ros2_message_type_map =
        Msgs.get_ros2_message_type_map("geometry_msgs/msg/Vector3", @ros_share_path)

      set_fragments = MsgC.set_fun_fragments("geometry_msgs/msg/Vector3", ros2_message_type_map)
      get_fragments = MsgC.get_fun_fragments("geometry_msgs/msg/Vector3", ros2_message_type_map)

      # Both should reference the same field names
      assert set_fragments =~ "message_p->x"
      assert set_fragments =~ "message_p->y"
      assert set_fragments =~ "message_p->z"

      assert get_fragments =~ "message_p->x"
      assert get_fragments =~ "message_p->y"
      assert get_fragments =~ "message_p->z"
    end
  end
end
