defmodule Rclex.Generators.MsgExTest do
  use ExUnit.Case
  doctest Rclex.Generators.MsgEx

  with ros_distro <- System.get_env("ROS_DISTRO"),
       true <- File.exists?("/opt/ros/#{ros_distro}") do
    @ros_share_path ["/opt/ros/#{ros_distro}/share"]
  else
    _ ->
      @moduletag :skip
  end

  alias Mix.Tasks.Rclex.Gen.Msgs
  alias Rclex.Generators.MsgEx
  alias Rclex.Generators.Util

  for ros2_message_type <- [
        "sensor_msgs/msg/PointCloud",
        "std_msgs/msg/Empty",
        "std_msgs/msg/String",
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

      binary = MsgEx.generate(ros2_message_type, ros2_message_type_map)

      assert "#{binary}" ==
               File.read!(Path.join(File.cwd!(), "test/expected_files/#{type_path}.ex"))
    end
  end

  describe "fields functions," do
    setup do
      %{
        ros2_message_type_map:
          Enum.reduce(
            [
              "std_msgs/msg/Empty",
              "std_msgs/msg/String",
              "std_msgs/msg/MultiArrayLayout",
              "std_msgs/msg/UInt32MultiArray",
              "geometry_msgs/msg/Vector3",
              "geometry_msgs/msg/Twist",
              "std_srvs/srv/SetBool_Request",
              "std_srvs/srv/SetBool_Response",
              "rcl_interfaces/msg/ParameterDescriptor",
              "rcl_interfaces/srv/GetParameterTypes_Request",
              "rcl_interfaces/srv/GetParameterTypes_Response"
            ],
            %{},
            fn type, acc ->
              Msgs.get_ros2_message_type_map(type, @ros_share_path, acc)
            end
          )
      }
    end

    for {ros2_message_type, expected} <- [
          {"std_msgs/msg/Empty", "[]"},
          {"std_msgs/msg/String", "data: \"\""},
          {"std_msgs/msg/MultiArrayDimension", "label: \"\",\nsize: 0,\nstride: 0"},
          {"std_msgs/msg/MultiArrayLayout", "dim: [],\ndata_offset: 0"},
          {"std_msgs/msg/UInt32MultiArray",
           "layout: %Rclex.Pkgs.StdMsgs.Msg.MultiArrayLayout{},\ndata: []"},
          {"geometry_msgs/msg/Vector3", "x: 0.0,\ny: 0.0,\nz: 0.0"},
          {"geometry_msgs/msg/Twist",
           "linear: %Rclex.Pkgs.GeometryMsgs.Msg.Vector3{},\nangular: %Rclex.Pkgs.GeometryMsgs.Msg.Vector3{}"}
        ] do
      test "defstruct_fields/2, #{ros2_message_type}", %{
        ros2_message_type_map: ros2_message_type_map
      } do
        fields = MsgEx.defstruct_fields(unquote(ros2_message_type), ros2_message_type_map)

        assert fields == "defstruct #{unquote(expected)}"
      end
    end

    for {ros2_message_type, expected} <- [
          {"std_msgs/msg/Empty", ""},
          {"std_msgs/msg/String", "data: String.t()"},
          {"std_msgs/msg/MultiArrayDimension",
           "label: String.t(),\nsize: non_neg_integer(),\nstride: non_neg_integer()"},
          {"std_msgs/msg/MultiArrayLayout",
           "dim: list(%Rclex.Pkgs.StdMsgs.Msg.MultiArrayDimension{}),\ndata_offset: non_neg_integer()"},
          {"std_msgs/msg/UInt32MultiArray",
           "layout: %Rclex.Pkgs.StdMsgs.Msg.MultiArrayLayout{},\ndata: list(non_neg_integer())"},
          {"geometry_msgs/msg/Vector3",
           "x: float() | :nan | :infinity | :neg_infinity,\ny: float() | :nan | :infinity | :neg_infinity,\nz: float() | :nan | :infinity | :neg_infinity"},
          {"geometry_msgs/msg/Twist",
           "linear: %Rclex.Pkgs.GeometryMsgs.Msg.Vector3{},\nangular: %Rclex.Pkgs.GeometryMsgs.Msg.Vector3{}"}
        ] do
      test "type_fields/2, #{ros2_message_type}", %{ros2_message_type_map: ros2_message_type_map} do
        fields = MsgEx.type_fields(unquote(ros2_message_type), ros2_message_type_map)

        assert fields == "@type t :: %__MODULE__{#{unquote(expected)}}"
      end
    end

    for {ros2_message_type, expected} <- [
          {"std_msgs/msg/Empty", ""},
          {"std_msgs/msg/String", "data: data"},
          {"std_msgs/msg/MultiArrayDimension", "label: label, size: size, stride: stride"},
          {"std_msgs/msg/MultiArrayLayout", "dim: dim, data_offset: data_offset"},
          {"std_msgs/msg/UInt32MultiArray", "layout: layout, data: data"},
          {"geometry_msgs/msg/Vector3", "x: x, y: y, z: z"},
          {"geometry_msgs/msg/Twist", "linear: linear, angular: angular"}
        ] do
      test "to_tuple_args_fields/2, #{ros2_message_type}", %{
        ros2_message_type_map: ros2_message_type_map
      } do
        assert MsgEx.to_tuple_args_fields(unquote(ros2_message_type), ros2_message_type_map) ==
                 unquote(expected)
      end
    end

    for {ros2_message_type, expected} <- [
          {"std_msgs/msg/Empty", ""},
          {"std_msgs/msg/String", "data"},
          {"std_msgs/msg/MultiArrayDimension", "label, size, stride"},
          {"std_msgs/msg/MultiArrayLayout", "dim, data_offset"},
          {"std_msgs/msg/UInt32MultiArray", "layout, data"},
          {"geometry_msgs/msg/Vector3", "x, y, z"},
          {"geometry_msgs/msg/Twist", "linear, angular"}
        ] do
      test "to_struct_args_fields/2, #{ros2_message_type}", %{
        ros2_message_type_map: ros2_message_type_map
      } do
        assert MsgEx.to_struct_args_fields(unquote(ros2_message_type), ros2_message_type_map) ==
                 unquote(expected)
      end
    end

    for {ros2_message_type, expected} <- [
          {"std_msgs/msg/Empty", ""},
          {"std_msgs/msg/String", "data"},
          {"std_msgs/msg/MultiArrayDimension", "label,\nsize,\nstride"},
          {"std_msgs/msg/MultiArrayLayout",
           "for struct <- dim do\n  Rclex.Pkgs.StdMsgs.Msg.MultiArrayDimension.to_tuple(struct)\nend,\ndata_offset"},
          {"std_msgs/msg/UInt32MultiArray",
           "Rclex.Pkgs.StdMsgs.Msg.MultiArrayLayout.to_tuple(layout),\ndata"},
          {"geometry_msgs/msg/Vector3", "x,\ny,\nz"},
          {"geometry_msgs/msg/Twist",
           "Rclex.Pkgs.GeometryMsgs.Msg.Vector3.to_tuple(linear),\nRclex.Pkgs.GeometryMsgs.Msg.Vector3.to_tuple(angular)"}
        ] do
      test "to_tuple_return_fields/2, #{ros2_message_type}", %{
        ros2_message_type_map: ros2_message_type_map
      } do
        fields = MsgEx.to_tuple_return_fields(unquote(ros2_message_type), ros2_message_type_map)

        assert fields == "{#{unquote(expected)}}"
      end
    end

    for {ros2_message_type, expected} <- [
          {"std_msgs/msg/Empty", ""},
          {"std_msgs/msg/String", "data: data"},
          {"std_msgs/msg/MultiArrayDimension", "label: label,\nsize: size,\nstride: stride"},
          {"std_msgs/msg/MultiArrayLayout",
           "dim:\n  for tuple <- dim do\n    Rclex.Pkgs.StdMsgs.Msg.MultiArrayDimension.to_struct(tuple)\n  end,\ndata_offset: data_offset"},
          {"std_msgs/msg/UInt32MultiArray",
           "layout: Rclex.Pkgs.StdMsgs.Msg.MultiArrayLayout.to_struct(layout),\ndata: data"},
          {"geometry_msgs/msg/Vector3", "x: x,\ny: y,\nz: z"},
          {"geometry_msgs/msg/Twist",
           "linear: Rclex.Pkgs.GeometryMsgs.Msg.Vector3.to_struct(linear),\nangular: Rclex.Pkgs.GeometryMsgs.Msg.Vector3.to_struct(angular)"}
        ] do
      test "to_struct_return_fields/2, #{ros2_message_type}", %{
        ros2_message_type_map: ros2_message_type_map
      } do
        fields = MsgEx.to_struct_return_fields(unquote(ros2_message_type), ros2_message_type_map)

        assert fields == "%__MODULE__{#{unquote(expected)}}"
      end
    end
  end

  describe "constants handling" do
    test "constant_fields/2 handles string constants" do
      ros2_constant_type_map = %{
        {:msg_type, "test/msg/WithConstants"} => [
          [{:builtin_type, "string"}, "TEST_STRING", "hello world"]
        ]
      }

      result = MsgEx.constant_fields("test/msg/WithConstants", ros2_constant_type_map)
      assert result =~ "def test_string, do: \"hello world\""
      refute result =~ "defguard"
    end

    test "constant_fields/2 handles numeric constants" do
      ros2_constant_type_map = %{
        {:msg_type, "test/msg/WithConstants"} => [
          [{:builtin_type, "int32"}, "MAX_VALUE", 100],
          [{:builtin_type, "float64"}, "PI_VALUE", 3.14159]
        ]
      }

      result = MsgEx.constant_fields("test/msg/WithConstants", ros2_constant_type_map)
      assert result =~ "def max_value, do: 100"
      assert result =~ "defguard is_max_value(value) when value == 100"
      assert result =~ "def pi_value, do: 3.14159"
      assert result =~ "defguard is_pi_value(value) when value == 3.14159"
    end

    test "constant_fields/2 handles empty constants" do
      result = MsgEx.constant_fields("test/msg/Empty", %{})
      assert result == ""
    end
  end

  describe "default value handling" do
    test "defstruct_builtin_type_field/2 handles all builtin types" do
      # This tests the private function behavior through defstruct_fields
      ros2_message_type_map = %{
        {:msg_type, "test/msg/AllTypes"} => [
          [{:builtin_type, "bool"}, "bool_field"],
          [{:builtin_type, "byte"}, "byte_field"],
          [{:builtin_type, "char"}, "char_field"],
          [{:builtin_type, "float32"}, "float32_field"],
          [{:builtin_type, "float64"}, "float64_field"],
          [{:builtin_type, "int8"}, "int8_field"],
          [{:builtin_type, "uint8"}, "uint8_field"],
          [{:builtin_type, "int16"}, "int16_field"],
          [{:builtin_type, "uint16"}, "uint16_field"],
          [{:builtin_type, "int32"}, "int32_field"],
          [{:builtin_type, "uint32"}, "uint32_field"],
          [{:builtin_type, "int64"}, "int64_field"],
          [{:builtin_type, "uint64"}, "uint64_field"],
          [{:builtin_type, "string"}, "string_field"],
          [{:builtin_type, "wstring"}, "wstring_field"]
        ]
      }

      result = MsgEx.defstruct_fields("test/msg/AllTypes", ros2_message_type_map)

      assert result =~ "bool_field: false"
      assert result =~ "byte_field: 0"
      assert result =~ "char_field: 0"
      assert result =~ "float32_field: 0.0"
      assert result =~ "float64_field: 0.0"
      assert result =~ "int8_field: 0"
      assert result =~ "uint8_field: 0"
      assert result =~ "int16_field: 0"
      assert result =~ "uint16_field: 0"
      assert result =~ "int32_field: 0"
      assert result =~ "uint32_field: 0"
      assert result =~ "int64_field: 0"
      assert result =~ "uint64_field: 0"
      assert result =~ "string_field: \"\""
      assert result =~ "wstring_field: \"\""
    end

    test "defstruct_fields/2 handles fields with default values" do
      ros2_message_type_map = %{
        {:msg_type, "test/msg/WithDefaults"} => [
          [{:builtin_type, "float32"}, "pi", 3.14],
          [{:builtin_type, "int32"}, "count", 42],
          [{:builtin_type, "string"}, "name", "default_name"],
          [{:builtin_type_array, "uint8[]"}, "data", [1, 2, 3]]
        ]
      }

      result = MsgEx.defstruct_fields("test/msg/WithDefaults", ros2_message_type_map)

      assert result =~ "pi: 3.14"
      assert result =~ "count: 42"
      assert result =~ "name: \"default_name\""
      assert result =~ "data: [1, 2, 3]"
    end

    test "defstruct_fields/2 handles uint8 arrays as binaries" do
      ros2_message_type_map = %{
        {:msg_type, "test/msg/BinaryData"} => [
          [{:builtin_type_array, "uint8[16]"}, "fixed_data"],
          [{:builtin_type_array, "uint8[]"}, "dynamic_data"]
        ]
      }

      result = MsgEx.defstruct_fields("test/msg/BinaryData", ros2_message_type_map)

      assert result =~ "fixed_data: <<>>"
      assert result =~ "dynamic_data: <<>>"
    end
  end

  describe "type specification generation" do
    test "type_fields/2 handles all builtin types" do
      ros2_message_type_map = %{
        {:msg_type, "test/msg/AllTypes"} => [
          [{:builtin_type, "bool"}, "bool_field"],
          [{:builtin_type, "byte"}, "byte_field"],
          [{:builtin_type, "char"}, "char_field"],
          [{:builtin_type, "float32"}, "float32_field"],
          [{:builtin_type, "float64"}, "float64_field"],
          [{:builtin_type, "int8"}, "int8_field"],
          [{:builtin_type, "uint8"}, "uint8_field"],
          [{:builtin_type, "int16"}, "int16_field"],
          [{:builtin_type, "uint16"}, "uint16_field"],
          [{:builtin_type, "int32"}, "int32_field"],
          [{:builtin_type, "uint32"}, "uint32_field"],
          [{:builtin_type, "int64"}, "int64_field"],
          [{:builtin_type, "uint64"}, "uint64_field"],
          [{:builtin_type, "string"}, "string_field"],
          [{:builtin_type, "wstring"}, "wstring_field"]
        ]
      }

      result = MsgEx.type_fields("test/msg/AllTypes", ros2_message_type_map)

      assert result =~ "bool_field: boolean()"
      assert result =~ "byte_field: byte()"
      assert result =~ "char_field: -128..127"
      assert result =~ "float32_field: float()"
      assert result =~ "float64_field: float()"
      assert result =~ "int8_field: -128..127"
      assert result =~ "uint8_field: byte()"
      assert result =~ "int16_field: integer()"
      assert result =~ "uint16_field: non_neg_integer()"
      assert result =~ "int32_field: integer()"
      assert result =~ "uint32_field: non_neg_integer()"
      assert result =~ "int64_field: integer()"
      assert result =~ "uint64_field: non_neg_integer()"
      assert result =~ "string_field: String.t()"
      assert result =~ "wstring_field: String.t()"
    end

    test "type_fields/2 handles array types" do
      ros2_message_type_map = %{
        {:msg_type, "test/msg/ArrayTypes"} => [
          [{:builtin_type_array, "uint8[16]"}, "fixed_bytes"],
          [{:builtin_type_array, "int32[]"}, "int_list"],
          [{:msg_type_array, "geometry_msgs/msg/Vector3[]"}, "vector_list"]
        ]
      }

      result = MsgEx.type_fields("test/msg/ArrayTypes", ros2_message_type_map)

      assert result =~ "fixed_bytes: binary()"
      assert result =~ "int_list: list(integer())"
      assert result =~ "vector_list: list(%Rclex.Pkgs.GeometryMsgs.Msg.Vector3{})"
    end

    test "type_fields/2 handles empty message" do
      ros2_message_type_map = %{
        {:msg_type, "std_msgs/msg/Empty"} => []
      }

      result = MsgEx.type_fields("std_msgs/msg/Empty", ros2_message_type_map)
      assert result == "@type t :: %__MODULE__{}"
    end
  end

  describe "conversion field generation" do
    test "to_tuple_args_fields/2 generates correct field mappings" do
      ros2_message_type_map = %{
        {:msg_type, "test/msg/Sample"} => [
          [{:builtin_type, "string"}, "name"],
          [{:builtin_type, "int32"}, "value"],
          [{:msg_type, "geometry_msgs/msg/Vector3"}, "position"]
        ]
      }

      result = MsgEx.to_tuple_args_fields("test/msg/Sample", ros2_message_type_map)
      assert result == "name: name, value: value, position: position"
    end

    test "to_struct_args_fields/2 generates correct argument list" do
      ros2_message_type_map = %{
        {:msg_type, "test/msg/Sample"} => [
          [{:builtin_type, "string"}, "name"],
          [{:builtin_type, "int32"}, "value"],
          [{:msg_type, "geometry_msgs/msg/Vector3"}, "position"]
        ]
      }

      result = MsgEx.to_struct_args_fields("test/msg/Sample", ros2_message_type_map)
      assert result == "name, value, position"
    end

    test "to_tuple_return_fields/2 handles nested conversions" do
      ros2_message_type_map = %{
        {:msg_type, "test/msg/Nested"} => [
          [{:builtin_type, "string"}, "name"],
          [{:msg_type, "geometry_msgs/msg/Vector3"}, "position"],
          [{:msg_type_array, "geometry_msgs/msg/Vector3[]"}, "waypoints"]
        ]
      }

      result = MsgEx.to_tuple_return_fields("test/msg/Nested", ros2_message_type_map)

      assert result =~ "name"
      assert result =~ "Rclex.Pkgs.GeometryMsgs.Msg.Vector3.to_tuple(position)"
      assert result =~ "for struct <- waypoints do"
      assert result =~ "Rclex.Pkgs.GeometryMsgs.Msg.Vector3.to_tuple(struct)"
    end

    test "to_struct_return_fields/2 handles nested conversions" do
      ros2_message_type_map = %{
        {:msg_type, "test/msg/Nested"} => [
          [{:builtin_type, "string"}, "name"],
          [{:msg_type, "geometry_msgs/msg/Vector3"}, "position"],
          [{:msg_type_array, "geometry_msgs/msg/Vector3[]"}, "waypoints"]
        ]
      }

      result = MsgEx.to_struct_return_fields("test/msg/Nested", ros2_message_type_map)

      assert result =~ "name: name"
      assert result =~ "position: Rclex.Pkgs.GeometryMsgs.Msg.Vector3.to_struct(position)"
      assert result =~ "waypoints:"
      assert result =~ "for tuple <- waypoints do"
      assert result =~ "Rclex.Pkgs.GeometryMsgs.Msg.Vector3.to_struct(tuple)"
    end

    test "conversion functions handle empty messages" do
      ros2_message_type_map = %{
        {:msg_type, "std_msgs/msg/Empty"} => []
      }

      assert MsgEx.to_tuple_args_fields("std_msgs/msg/Empty", ros2_message_type_map) == ""
      assert MsgEx.to_struct_args_fields("std_msgs/msg/Empty", ros2_message_type_map) == ""
      assert MsgEx.to_tuple_return_fields("std_msgs/msg/Empty", ros2_message_type_map) == "{}"

      assert MsgEx.to_struct_return_fields("std_msgs/msg/Empty", ros2_message_type_map) ==
               "%__MODULE__{}"
    end
  end

  describe "array handling" do
    test "handles uint8 arrays as binary" do
      ros2_message_type_map = %{
        {:msg_type, "test/msg/BinaryMsg"} => [
          [{:builtin_type_array, "uint8[256]"}, "image_data"],
          [{:builtin_type_array, "uint8[]"}, "dynamic_data"]
        ]
      }

      # Test defstruct generation
      defstruct_result = MsgEx.defstruct_fields("test/msg/BinaryMsg", ros2_message_type_map)
      assert defstruct_result =~ "image_data: <<>>"
      assert defstruct_result =~ "dynamic_data: <<>>"

      # Test type specification
      type_result = MsgEx.type_fields("test/msg/BinaryMsg", ros2_message_type_map)
      assert type_result =~ "image_data: binary()"
      assert type_result =~ "dynamic_data: binary()"

      # Test conversion functions
      tuple_return_result =
        MsgEx.to_tuple_return_fields("test/msg/BinaryMsg", ros2_message_type_map)

      assert tuple_return_result =~ "image_data"
      assert tuple_return_result =~ "dynamic_data"
    end

    test "handles other array types correctly" do
      ros2_message_type_map = %{
        {:msg_type, "test/msg/ArrayMsg"} => [
          [{:builtin_type_array, "int32[]"}, "numbers"],
          [{:builtin_type_array, "float64[10]"}, "coordinates"],
          [{:msg_type_array, "std_msgs/msg/String[]"}, "messages"]
        ]
      }

      # Test defstruct generation
      defstruct_result = MsgEx.defstruct_fields("test/msg/ArrayMsg", ros2_message_type_map)
      assert defstruct_result =~ "numbers: []"
      assert defstruct_result =~ "coordinates: []"
      assert defstruct_result =~ "messages: []"

      # Test type specification
      type_result = MsgEx.type_fields("test/msg/ArrayMsg", ros2_message_type_map)
      assert type_result =~ "numbers: list(integer())"

      assert type_result =~
               "coordinates: list(float() | :nan | :infinity | :neg_infinity)"

      assert type_result =~ "messages: list(%Rclex.Pkgs.StdMsgs.Msg.String{})"
    end
  end

  describe "code generation and formatting" do
    test "generate/2 emits a bounded string length guard" do
      ros2_message_type_map = %{
        {:msg_type, "test/msg/BoundedString"} => [
          [{:builtin_type, "string<=255"}, "nested_type_name"]
        ]
      }

      result = MsgEx.generate("test/msg/BoundedString", ros2_message_type_map)

      assert result =~
               "defguard is_nested_type_name(value) when is_binary(value) and byte_size(value) <= 255"

      assert result =~ "defstruct nested_type_name: \"\""
      assert result =~ "@type t :: %__MODULE__{nested_type_name: String.t()}"

      assert result =~ "def to_tuple(%__MODULE__{nested_type_name: nested_type_name})"
      assert result =~ "when is_nested_type_name(nested_type_name) do"
    end

    test "generate/3 produces valid, formatted Elixir code" do
      ros2_message_type_map =
        Msgs.get_ros2_message_type_map("std_msgs/msg/String", @ros_share_path)

      result = MsgEx.generate("std_msgs/msg/String", ros2_message_type_map, %{})

      # Should be valid Elixir syntax
      assert result =~ "defmodule Rclex.Pkgs.StdMsgs.Msg.String do"
      assert result =~ "defstruct data: \"\""
      assert result =~ "@type t :: %__MODULE__{data: String.t()}"
      assert result =~ "def type_support!"
      assert result =~ "def create!"
      assert result =~ "def destroy!"
      assert result =~ "def set!"
      assert result =~ "def get!"
      assert result =~ "def to_tuple"
      assert result =~ "def to_struct"

      # Should end with newline
      assert String.ends_with?(result, "\n")
    end

    test "generate/2 works without constants" do
      ros2_message_type_map =
        Msgs.get_ros2_message_type_map("std_msgs/msg/Empty", @ros_share_path)

      result = MsgEx.generate("std_msgs/msg/Empty", ros2_message_type_map)

      assert result =~ "defmodule Rclex.Pkgs.StdMsgs.Msg.Empty do"
      assert result =~ "defstruct []"
      assert result =~ "@type t :: %__MODULE__{}"
    end

    test "generates proper module names" do
      # Test with various message types to ensure module naming is correct
      test_cases = [
        {"std_msgs/msg/String", "Rclex.Pkgs.StdMsgs.Msg.String"},
        {"geometry_msgs/msg/Vector3", "Rclex.Pkgs.GeometryMsgs.Msg.Vector3"},
        {"sensor_msgs/msg/PointCloud", "Rclex.Pkgs.SensorMsgs.Msg.PointCloud"},
        {"tf2_msgs/action/LookupTransform_Goal", "Rclex.Pkgs.Tf2Msgs.Action.LookupTransform.Goal"}
      ]

      for {msg_type, expected_module} <- test_cases do
        ros2_message_type_map = Msgs.get_ros2_message_type_map(msg_type, @ros_share_path)
        result = MsgEx.generate(msg_type, ros2_message_type_map, %{})
        assert result =~ "defmodule #{expected_module} do"
      end
    end
  end

  describe "edge cases and error handling" do
    test "handles messages with no fields gracefully" do
      ros2_message_type_map = %{
        {:msg_type, "test/msg/Empty"} => []
      }

      # All functions should handle empty field lists
      assert MsgEx.defstruct_fields("test/msg/Empty", ros2_message_type_map) == "defstruct []"

      assert MsgEx.type_fields("test/msg/Empty", ros2_message_type_map) ==
               "@type t :: %__MODULE__{}"

      assert MsgEx.to_tuple_args_fields("test/msg/Empty", ros2_message_type_map) == ""
      assert MsgEx.to_struct_args_fields("test/msg/Empty", ros2_message_type_map) == ""
      assert MsgEx.to_tuple_return_fields("test/msg/Empty", ros2_message_type_map) == "{}"

      assert MsgEx.to_struct_return_fields("test/msg/Empty", ros2_message_type_map) ==
               "%__MODULE__{}"
    end

    test "constant_fields handles missing constants" do
      result = MsgEx.constant_fields("test/msg/NoConstants", %{})
      assert result == ""
    end
  end
end
