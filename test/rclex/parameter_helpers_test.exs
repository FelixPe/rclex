defmodule Rclex.ParameterHelpersTest do
  use ExUnit.Case, async: true

  alias Rclex.ParameterHelpers
  alias Rclex.Pkgs.BuiltinInterfaces.Msg.Time

  alias Rclex.Pkgs.RclInterfaces.Msg.{
    ParameterType,
    ParameterValue,
    ParameterDescriptor,
    ParameterEvent,
    SetParametersResult
  }

  alias Rclex.ParameterHelpers
  alias Rclex.Pkgs.RclInterfaces.Msg.Parameter, as: ParameterMsg

  doctest Rclex.ParameterHelpers

  describe "gen_parameter_struct/2 with automatic type inference" do
    test "creates boolean parameter" do
      param =
        ParameterHelpers.gen_parameter_struct(
          "test_bool",
          ParameterHelpers.gen_parameter_value_struct(true)
        )

      assert param.name == "test_bool"
      assert param.value.type == ParameterType.parameter_bool()
      assert param.value.bool_value == true
      assert param.value.integer_value == 0
      assert param.value.double_value == 0.0
      assert param.value.string_value == ""
    end

    test "creates integer parameter" do
      param =
        ParameterHelpers.gen_parameter_struct(
          "test_int",
          ParameterHelpers.gen_parameter_value_struct(42)
        )

      assert param.name == "test_int"
      assert param.value.type == ParameterType.parameter_integer()
      assert param.value.bool_value == false
      assert param.value.integer_value == 42
      assert param.value.double_value == 0.0
      assert param.value.string_value == ""
    end

    test "creates double parameter" do
      param =
        ParameterHelpers.gen_parameter_struct(
          "test_double",
          ParameterHelpers.gen_parameter_value_struct(3.14)
        )

      assert param.name == "test_double"
      assert param.value.type == ParameterType.parameter_double()
      assert param.value.bool_value == false
      assert param.value.integer_value == 0
      assert param.value.double_value == 3.14
      assert param.value.string_value == ""
    end

    test "creates string parameter" do
      param =
        ParameterHelpers.gen_parameter_struct(
          "test_string",
          ParameterHelpers.gen_parameter_value_struct("hello")
        )

      assert param.name == "test_string"
      assert param.value.type == ParameterType.parameter_string()
      assert param.value.bool_value == false
      assert param.value.integer_value == 0
      assert param.value.double_value == 0.0
      assert param.value.string_value == "hello"
    end

    test "creates byte array parameter" do
      param =
        ParameterHelpers.gen_parameter_struct(
          "test_bytes",
          ParameterHelpers.gen_parameter_value_struct([1, 2, 3, 255])
        )

      assert param.name == "test_bytes"
      assert param.value.type == ParameterType.parameter_byte_array()
      assert param.value.byte_array_value == [1, 2, 3, 255]
      assert param.value.bool_array_value == []
      assert param.value.integer_array_value == []
    end

    test "creates boolean array parameter" do
      param =
        ParameterHelpers.gen_parameter_struct(
          "test_bool_array",
          ParameterHelpers.gen_parameter_value_struct([true, false, true])
        )

      assert param.name == "test_bool_array"
      assert param.value.type == ParameterType.parameter_bool_array()
      assert param.value.bool_array_value == [true, false, true]
      assert param.value.byte_array_value == []
      assert param.value.integer_array_value == []
    end

    test "creates integer array parameter" do
      param =
        ParameterHelpers.gen_parameter_struct(
          "test_int_array",
          ParameterHelpers.gen_parameter_value_struct([1, 2, 3, 300])
        )

      assert param.name == "test_int_array"
      assert param.value.type == ParameterType.parameter_integer_array()
      assert param.value.integer_array_value == [1, 2, 3, 300]
      assert param.value.bool_array_value == []
      assert param.value.double_array_value == []
    end

    test "creates double array parameter" do
      param =
        ParameterHelpers.gen_parameter_struct(
          "test_double_array",
          ParameterHelpers.gen_parameter_value_struct([1.1, 2.2, 3.3])
        )

      assert param.name == "test_double_array"
      assert param.value.type == ParameterType.parameter_double_array()
      assert param.value.double_array_value == [1.1, 2.2, 3.3]
      assert param.value.integer_array_value == []
      assert param.value.string_array_value == []
    end

    test "creates string array parameter" do
      param =
        ParameterHelpers.gen_parameter_struct(
          "test_string_array",
          ParameterHelpers.gen_parameter_value_struct(["hello", "world"])
        )

      assert param.name == "test_string_array"
      assert param.value.type == ParameterType.parameter_string_array()
      assert param.value.string_array_value == ["hello", "world"]
      assert param.value.double_array_value == []
      assert param.value.bool_array_value == []
    end

    test "creates not_set parameter for empty list" do
      param =
        ParameterHelpers.gen_parameter_struct(
          "test_empty",
          ParameterHelpers.gen_parameter_value_struct([])
        )

      assert param.name == "test_empty"
      assert param.value.type == ParameterType.parameter_not_set()
      assert param.value.bool_value == false
      assert param.value.integer_value == 0
    end

    test "creates not_set parameter for nil" do
      param =
        ParameterHelpers.gen_parameter_struct(
          "test_nil",
          ParameterHelpers.gen_parameter_value_struct(nil)
        )

      assert param.name == "test_nil"
      assert param.value.type == ParameterType.parameter_not_set()
      assert param.value.bool_value == false
      assert param.value.integer_value == 0
    end

    test "distinguishes between byte array and integer array" do
      # Byte array (all values 0-255)
      byte_param =
        ParameterHelpers.gen_parameter_struct(
          "bytes",
          ParameterHelpers.gen_parameter_value_struct([1, 2, 255])
        )

      assert byte_param.value.type == ParameterType.parameter_byte_array()
      assert byte_param.value.byte_array_value == [1, 2, 255]

      # Integer array (contains values > 255)
      int_param =
        ParameterHelpers.gen_parameter_struct(
          "ints",
          ParameterHelpers.gen_parameter_value_struct([1, 2, 256], :integer_array)
        )

      assert int_param.value.type == ParameterType.parameter_integer_array()
      assert int_param.value.integer_array_value == [1, 2, 256]
    end

    test "handles mixed lists gracefully" do
      # Mixed list should use first element type
      param =
        ParameterHelpers.gen_parameter_struct(
          "mixed",
          ParameterHelpers.gen_parameter_value_struct([1, "string", true])
        )

      assert param.value.type == ParameterType.parameter_integer_array()
    end
  end

  describe "gen_parameter_struct/3 with explicit type specification" do
    test "creates parameter with explicit bool type" do
      param =
        ParameterHelpers.gen_parameter_struct(
          "test_bool",
          ParameterHelpers.gen_parameter_value_struct(true, :boolean)
        )

      assert param.name == "test_bool"
      assert param.value.type == ParameterType.parameter_bool()
      assert param.value.bool_value == true
    end

    test "creates parameter with explicit integer type" do
      param =
        ParameterHelpers.gen_parameter_struct(
          "test_int",
          ParameterHelpers.gen_parameter_value_struct("42", :integer)
        )

      assert param.name == "test_int"
      assert param.value.type == ParameterType.parameter_integer()
      assert param.value.integer_value == "42"
    end

    test "creates parameter with explicit double type" do
      param =
        ParameterHelpers.gen_parameter_struct(
          "test_double",
          ParameterHelpers.gen_parameter_value_struct(42, :float)
        )

      assert param.name == "test_double"
      assert param.value.type == ParameterType.parameter_double()
      assert param.value.double_value == 42
    end

    test "creates parameter with explicit string type" do
      param =
        ParameterHelpers.gen_parameter_struct(
          "test_string",
          ParameterHelpers.gen_parameter_value_struct(42, :string)
        )

      assert param.name == "test_string"
      assert param.value.type == ParameterType.parameter_string()
      assert param.value.string_value == "42"
    end

    test "creates parameter with explicit byte_array type" do
      param =
        ParameterHelpers.gen_parameter_struct(
          "test_bytes",
          ParameterHelpers.gen_parameter_value_struct([1, 2, 300], :byte_array)
        )

      assert param.name == "test_bytes"
      assert param.value.type == ParameterType.parameter_byte_array()
      assert param.value.byte_array_value == [1, 2, 300]
    end

    test "creates parameter with explicit bool_array type" do
      param =
        ParameterHelpers.gen_parameter_struct(
          "test_bool_array",
          ParameterHelpers.gen_parameter_value_struct([1, 0, "true"], :boolean_array)
        )

      assert param.name == "test_bool_array"
      assert param.value.type == ParameterType.parameter_bool_array()
      assert param.value.bool_array_value == [true, false, true]
    end

    test "creates parameter with explicit integer_array type" do
      param =
        ParameterHelpers.gen_parameter_struct(
          "test_int_array",
          ParameterHelpers.gen_parameter_value_struct([1.1, 2.2], :integer_array)
        )

      assert param.name == "test_int_array"
      assert param.value.type == ParameterType.parameter_integer_array()
      assert param.value.integer_array_value == [1.1, 2.2]
    end

    test "creates parameter with explicit double_array type" do
      param =
        ParameterHelpers.gen_parameter_struct(
          "test_double_array",
          ParameterHelpers.gen_parameter_value_struct([1, 2], :float_array)
        )

      assert param.name == "test_double_array"
      assert param.value.type == ParameterType.parameter_double_array()
      assert param.value.double_array_value == [1, 2]
    end

    test "creates parameter with explicit string_array type" do
      param =
        ParameterHelpers.gen_parameter_struct(
          "test_string_array",
          ParameterHelpers.gen_parameter_value_struct([1, 2], :string_array)
        )

      assert param.name == "test_string_array"
      assert param.value.type == ParameterType.parameter_string_array()
      assert param.value.string_array_value == [1, 2]
    end

    test "creates parameter with explicit not_set type" do
      param =
        ParameterHelpers.gen_parameter_struct(
          "test_not_set",
          ParameterHelpers.gen_parameter_value_struct("any_value", :not_set)
        )

      assert param.name == "test_not_set"
      assert param.value.type == ParameterType.parameter_not_set()
      assert param.value.bool_value == false
      assert param.value.integer_value == 0
    end
  end

  describe "gen_parameter_value_struct/1 with automatic type inference" do
    test "creates boolean parameter value" do
      param_value = ParameterHelpers.gen_parameter_value_struct(true)

      assert param_value.type == ParameterType.parameter_bool()
      assert param_value.bool_value == true
      assert param_value.integer_value == 0
      assert param_value.double_value == 0.0
      assert param_value.string_value == ""
    end

    test "creates integer parameter value" do
      param_value = ParameterHelpers.gen_parameter_value_struct(42)

      assert param_value.type == ParameterType.parameter_integer()
      assert param_value.bool_value == false
      assert param_value.integer_value == 42
      assert param_value.double_value == 0.0
      assert param_value.string_value == ""
    end

    test "creates double parameter value" do
      param_value = ParameterHelpers.gen_parameter_value_struct(3.14)

      assert param_value.type == ParameterType.parameter_double()
      assert param_value.bool_value == false
      assert param_value.integer_value == 0
      assert param_value.double_value == 3.14
      assert param_value.string_value == ""
    end

    test "creates string parameter value" do
      param_value = ParameterHelpers.gen_parameter_value_struct("hello")

      assert param_value.type == ParameterType.parameter_string()
      assert param_value.bool_value == false
      assert param_value.integer_value == 0
      assert param_value.double_value == 0.0
      assert param_value.string_value == "hello"
    end

    test "creates arrays based on first element type" do
      # Boolean array
      bool_array = ParameterHelpers.gen_parameter_value_struct([true, false])
      assert bool_array.type == ParameterType.parameter_bool_array()
      assert bool_array.bool_array_value == [true, false]

      # Integer array
      int_array = ParameterHelpers.gen_parameter_value_struct([100, 200, 300])
      assert int_array.type == ParameterType.parameter_integer_array()
      assert int_array.integer_array_value == [100, 200, 300]

      # Double array
      double_array = ParameterHelpers.gen_parameter_value_struct([1.1, 2.2])
      assert double_array.type == ParameterType.parameter_double_array()
      assert double_array.double_array_value == [1.1, 2.2]

      # String array
      string_array = ParameterHelpers.gen_parameter_value_struct(["hello", "world"])
      assert string_array.type == ParameterType.parameter_string_array()
      assert string_array.string_array_value == ["hello", "world"]
    end

    test "creates byte array for values 0-255" do
      param_value = ParameterHelpers.gen_parameter_value_struct([0, 128, 255])

      assert param_value.type == ParameterType.parameter_byte_array()
      assert param_value.byte_array_value == [0, 128, 255]
    end

    test "creates integer array for values outside byte range" do
      param_value = ParameterHelpers.gen_parameter_value_struct([0, 128, 256])

      assert param_value.type == ParameterType.parameter_integer_array()
      assert param_value.integer_array_value == [0, 128, 256]
    end

    test "creates not_set for empty list" do
      param_value = ParameterHelpers.gen_parameter_value_struct([])

      assert param_value.type == ParameterType.parameter_not_set()
    end

    test "creates not_set for unknown types" do
      param_value = ParameterHelpers.gen_parameter_value_struct(%{key: "value"})

      assert param_value.type == ParameterType.parameter_not_set()
      assert param_value.string_value == "%{key: \"value\"}"
    end
  end

  describe "gen_parameter_value_struct/2 with explicit type" do
    test "creates boolean value with type coercion" do
      # Truthy values become true
      param_value = ParameterHelpers.gen_parameter_value_struct(1, :boolean)
      assert param_value.type == ParameterType.parameter_bool()
      assert param_value.bool_value == true

      # Falsy values become false
      param_value = ParameterHelpers.gen_parameter_value_struct(false, :boolean)
      assert param_value.type == ParameterType.parameter_bool()
      assert param_value.bool_value == false

      param_value = ParameterHelpers.gen_parameter_value_struct(nil, :boolean)
      assert param_value.type == ParameterType.parameter_bool()
      assert param_value.bool_value == false
    end

    test "creates string value with string conversion" do
      param_value = ParameterHelpers.gen_parameter_value_struct(42, :string)

      assert param_value.type == ParameterType.parameter_string()
      assert param_value.string_value == "42"
    end

    test "creates array types with explicit specification" do
      # Force byte array
      param_value = ParameterHelpers.gen_parameter_value_struct([1, 2, 300], :byte_array)
      assert param_value.type == ParameterType.parameter_byte_array()
      assert param_value.byte_array_value == [1, 2, 300]

      # Force bool array
      param_value = ParameterHelpers.gen_parameter_value_struct([1, 0], :boolean_array)
      assert param_value.type == ParameterType.parameter_bool_array()
      assert param_value.bool_array_value == [true, false]

      # Force integer array
      param_value = ParameterHelpers.gen_parameter_value_struct([1.1, 2.2], :integer_array)
      assert param_value.type == ParameterType.parameter_integer_array()
      assert param_value.integer_array_value == [1.1, 2.2]

      # Force double array
      param_value = ParameterHelpers.gen_parameter_value_struct([1, 2], :float_array)
      assert param_value.type == ParameterType.parameter_double_array()
      assert param_value.double_array_value == [1, 2]

      # Force string array
      param_value = ParameterHelpers.gen_parameter_value_struct([1, 2], :string_array)
      assert param_value.type == ParameterType.parameter_string_array()
      assert param_value.string_array_value == [1, 2]
    end

    test "creates not_set type explicitly" do
      param_value = ParameterHelpers.gen_parameter_value_struct("any_value", :not_set)

      assert param_value.type == ParameterType.parameter_not_set()
    end

    test "falls back to automatic inference for unknown type" do
      param_value = ParameterHelpers.gen_parameter_value_struct(42, :unknown_type)

      assert param_value.type == ParameterType.parameter_integer()
      assert param_value.integer_value == 42
    end
  end

  describe "gen_parameter_descriptor_struct/2" do
    test "creates basic descriptor with defaults" do
      descriptor = ParameterHelpers.gen_parameter_descriptor_struct("my_param")

      assert descriptor.name == "my_param"
      assert descriptor.type == ParameterType.parameter_not_set()
      assert descriptor.description == ""
      assert descriptor.additional_constraints == ""
      assert descriptor.read_only == false
      assert descriptor.dynamic_typing == false
    end

    test "creates descriptor with custom options" do
      opts = [
        description: "A test parameter",
        additional_constraints: "Must be positive",
        read_only: true,
        dynamic_typing: true
      ]

      descriptor = ParameterHelpers.gen_parameter_descriptor_struct("my_param", :integer, opts)

      assert descriptor.name == "my_param"
      assert descriptor.type == ParameterType.parameter_integer()
      assert descriptor.description == "A test parameter"
      assert descriptor.additional_constraints == "Must be positive"
      assert descriptor.read_only == true
      assert descriptor.dynamic_typing == true
    end

    test "creates descriptor with partial options" do
      descriptor =
        ParameterHelpers.gen_parameter_descriptor_struct("param", :not_set,
          description: "Test param",
          read_only: true
        )

      assert descriptor.name == "param"
      assert descriptor.type == ParameterType.parameter_not_set()
      assert descriptor.description == "Test param"
      assert descriptor.additional_constraints == ""
      assert descriptor.read_only == true
      assert descriptor.dynamic_typing == false
    end
  end

  describe "gen_parameter_event_struct/5" do
    test "creates parameter event with timestamp" do
      new_params = [ParameterHelpers.gen_parameter_struct("new_param", 42)]
      changed_params = [ParameterHelpers.gen_parameter_struct("changed_param", "hello")]
      deleted_params = [ParameterHelpers.gen_parameter_struct("deleted_param", true)]

      event =
        ParameterHelpers.gen_parameter_event_struct(
          "/test_namespace/test_node",
          %Time{
            sec: 1_234_567_890,
            nanosec: 123_456_789
          },
          new_params,
          changed_params,
          deleted_params
        )

      assert event.node == "/test_namespace/test_node"
      assert event.new_parameters == new_params
      assert event.changed_parameters == changed_params
      assert event.deleted_parameters == deleted_params
      assert is_map(event.stamp)
      assert is_integer(event.stamp.sec)
      assert is_integer(event.stamp.nanosec)
    end

    test "creates parameter event with empty lists" do
      event =
        ParameterHelpers.gen_parameter_event_struct(
          "/node",
          %Time{
            sec: 1_234_567_890,
            nanosec: 123_456_789
          },
          [],
          [],
          []
        )

      assert event.node == "/node"
      assert event.new_parameters == []
      assert event.changed_parameters == []
      assert event.deleted_parameters == []
    end
  end

  describe "gen_set_parameters_result_struct/2" do
    test "creates successful result" do
      result = ParameterHelpers.gen_set_parameters_result_struct(true, "Success")

      assert result.successful == true
      assert result.reason == "Success"
    end

    test "creates failed result" do
      result =
        ParameterHelpers.gen_set_parameters_result_struct(false, "Parameter validation failed")

      assert result.successful == false
      assert result.reason == "Parameter validation failed"
    end

    test "creates result with default reason" do
      result = ParameterHelpers.gen_set_parameters_result_struct(true)

      assert result.successful == true
      assert result.reason == ""
    end
  end

  describe "parameter_type_to_ros2/1" do
    test "converts parameter type atoms to ROS2 constants" do
      assert ParameterHelpers.parameter_type_to_ros2(:not_set) ==
               ParameterType.parameter_not_set()

      assert ParameterHelpers.parameter_type_to_ros2(:boolean) == ParameterType.parameter_bool()

      assert ParameterHelpers.parameter_type_to_ros2(:integer) ==
               ParameterType.parameter_integer()

      assert ParameterHelpers.parameter_type_to_ros2(:float) == ParameterType.parameter_double()
      assert ParameterHelpers.parameter_type_to_ros2(:string) == ParameterType.parameter_string()

      assert ParameterHelpers.parameter_type_to_ros2(:byte_array) ==
               ParameterType.parameter_byte_array()

      assert ParameterHelpers.parameter_type_to_ros2(:boolean_array) ==
               ParameterType.parameter_bool_array()

      assert ParameterHelpers.parameter_type_to_ros2(:integer_array) ==
               ParameterType.parameter_integer_array()

      assert ParameterHelpers.parameter_type_to_ros2(:float_array) ==
               ParameterType.parameter_double_array()

      assert ParameterHelpers.parameter_type_to_ros2(:string_array) ==
               ParameterType.parameter_string_array()
    end

    test "returns not_set for unknown types" do
      assert ParameterHelpers.parameter_type_to_ros2(:unknown) ==
               ParameterType.parameter_not_set()

      assert ParameterHelpers.parameter_type_to_ros2(:invalid) ==
               ParameterType.parameter_not_set()
    end
  end

  describe "ros2_to_parameter_type/1" do
    test "converts ROS2 constants to parameter type atoms" do
      assert ParameterHelpers.ros2_to_parameter_type(ParameterType.parameter_not_set()) ==
               :not_set

      assert ParameterHelpers.ros2_to_parameter_type(ParameterType.parameter_bool()) == :boolean

      assert ParameterHelpers.ros2_to_parameter_type(ParameterType.parameter_integer()) ==
               :integer

      assert ParameterHelpers.ros2_to_parameter_type(ParameterType.parameter_double()) == :float
      assert ParameterHelpers.ros2_to_parameter_type(ParameterType.parameter_string()) == :string

      assert ParameterHelpers.ros2_to_parameter_type(ParameterType.parameter_byte_array()) ==
               :byte_array

      assert ParameterHelpers.ros2_to_parameter_type(ParameterType.parameter_bool_array()) ==
               :boolean_array

      assert ParameterHelpers.ros2_to_parameter_type(ParameterType.parameter_integer_array()) ==
               :integer_array

      assert ParameterHelpers.ros2_to_parameter_type(ParameterType.parameter_double_array()) ==
               :float_array

      assert ParameterHelpers.ros2_to_parameter_type(ParameterType.parameter_string_array()) ==
               :string_array
    end

    test "returns not_set for unknown constants" do
      assert ParameterHelpers.ros2_to_parameter_type(999) == :not_set
      assert ParameterHelpers.ros2_to_parameter_type(-1) == :not_set
    end
  end

  describe "parameter_value_to_elixir/1" do
    test "extracts boolean value" do
      param_value = %ParameterValue{
        type: ParameterType.parameter_bool(),
        bool_value: true
      }

      assert ParameterHelpers.parameter_value_to_elixir(param_value) == true
    end

    test "extracts integer value" do
      param_value = %ParameterValue{
        type: ParameterType.parameter_integer(),
        integer_value: 42
      }

      assert ParameterHelpers.parameter_value_to_elixir(param_value) == 42
    end

    test "extracts double value" do
      param_value = %ParameterValue{
        type: ParameterType.parameter_double(),
        double_value: 3.14
      }

      assert ParameterHelpers.parameter_value_to_elixir(param_value) == 3.14
    end

    test "extracts string value" do
      param_value = %ParameterValue{
        type: ParameterType.parameter_string(),
        string_value: "hello"
      }

      assert ParameterHelpers.parameter_value_to_elixir(param_value) == "hello"
    end

    test "extracts array values" do
      # Byte array
      byte_param = %ParameterValue{
        type: ParameterType.parameter_byte_array(),
        byte_array_value: [1, 2, 3]
      }

      assert ParameterHelpers.parameter_value_to_elixir(byte_param) == [1, 2, 3]

      # Boolean array
      bool_param = %ParameterValue{
        type: ParameterType.parameter_bool_array(),
        bool_array_value: [true, false]
      }

      assert ParameterHelpers.parameter_value_to_elixir(bool_param) == [true, false]

      # Integer array
      int_param = %ParameterValue{
        type: ParameterType.parameter_integer_array(),
        integer_array_value: [1, 2, 3]
      }

      assert ParameterHelpers.parameter_value_to_elixir(int_param) == [1, 2, 3]

      # Double array
      double_param = %ParameterValue{
        type: ParameterType.parameter_double_array(),
        double_array_value: [1.1, 2.2]
      }

      assert ParameterHelpers.parameter_value_to_elixir(double_param) == [1.1, 2.2]

      # String array
      string_param = %ParameterValue{
        type: ParameterType.parameter_string_array(),
        string_array_value: ["hello", "world"]
      }

      assert ParameterHelpers.parameter_value_to_elixir(string_param) == ["hello", "world"]
    end

    test "returns nil for not_set parameters" do
      param_value = %ParameterValue{
        type: ParameterType.parameter_not_set()
      }

      assert ParameterHelpers.parameter_value_to_elixir(param_value) == nil
    end

    test "returns nil for unknown types" do
      param_value = %ParameterValue{
        type: 999
      }

      assert ParameterHelpers.parameter_value_to_elixir(param_value) == nil
    end
  end

  describe "parameter_to_elixir/1" do
    test "extracts name and value from parameter" do
      param = %ParameterMsg{
        name: "test_param",
        value: %ParameterValue{
          type: ParameterType.parameter_integer(),
          integer_value: 42
        }
      }

      assert ParameterHelpers.parameter_to_elixir(param) == {"test_param", 42}
    end

    test "handles different parameter types" do
      # Boolean parameter
      bool_param = %ParameterMsg{
        name: "bool_param",
        value: %ParameterValue{
          type: ParameterType.parameter_bool(),
          bool_value: true
        }
      }

      assert ParameterHelpers.parameter_to_elixir(bool_param) == {"bool_param", true}

      # String parameter
      string_param = %ParameterMsg{
        name: "string_param",
        value: %ParameterValue{
          type: ParameterType.parameter_string(),
          string_value: "hello"
        }
      }

      assert ParameterHelpers.parameter_to_elixir(string_param) == {"string_param", "hello"}

      # Array parameter
      array_param = %ParameterMsg{
        name: "array_param",
        value: %ParameterValue{
          type: ParameterType.parameter_integer_array(),
          integer_array_value: [1, 2, 3]
        }
      }

      assert ParameterHelpers.parameter_to_elixir(array_param) == {"array_param", [1, 2, 3]}
    end
  end

  describe "valid_parameter_name?/1" do
    test "accepts valid parameter names" do
      assert ParameterHelpers.valid_parameter_name?("param")
      assert ParameterHelpers.valid_parameter_name?("my_param")
      assert ParameterHelpers.valid_parameter_name?("param123")
      assert ParameterHelpers.valid_parameter_name?("param_with_underscores")
      assert ParameterHelpers.valid_parameter_name?("param.with.dots")
      assert ParameterHelpers.valid_parameter_name?("param_123.test")
      assert ParameterHelpers.valid_parameter_name?("_private_param")
      assert ParameterHelpers.valid_parameter_name?("ParamWithCaps")
    end

    test "rejects invalid parameter names" do
      # starts with number
      assert not ParameterHelpers.valid_parameter_name?("123param")
      # starts with dash
      assert not ParameterHelpers.valid_parameter_name?("-param")
      # contains dashes
      assert not ParameterHelpers.valid_parameter_name?("param-with-dashes")
      # contains spaces
      assert not ParameterHelpers.valid_parameter_name?("param with spaces")
      # contains special chars
      assert not ParameterHelpers.valid_parameter_name?("param@special")
      # empty string
      assert not ParameterHelpers.valid_parameter_name?("")
      # starts with dot
      assert not ParameterHelpers.valid_parameter_name?(".param")
    end

    test "rejects non-string inputs" do
      assert not ParameterHelpers.valid_parameter_name?(123)
      assert not ParameterHelpers.valid_parameter_name?(nil)
      assert not ParameterHelpers.valid_parameter_name?(:param)
      assert not ParameterHelpers.valid_parameter_name?([])
    end
  end

  describe "parameter_values_equal?/2" do
    test "returns true for identical parameter values" do
      param_value1 = %ParameterValue{
        type: ParameterType.parameter_integer(),
        integer_value: 42
      }

      param_value2 = %ParameterValue{
        type: ParameterType.parameter_integer(),
        integer_value: 42
      }

      assert ParameterHelpers.parameter_values_equal?(param_value1, param_value2)
    end

    test "returns false for different types" do
      param_value1 = %ParameterValue{
        type: ParameterType.parameter_integer(),
        integer_value: 42
      }

      param_value2 = %ParameterValue{
        type: ParameterType.parameter_string(),
        string_value: "42"
      }

      assert not ParameterHelpers.parameter_values_equal?(param_value1, param_value2)
    end

    test "returns false for different values" do
      param_value1 = %ParameterValue{
        type: ParameterType.parameter_integer(),
        integer_value: 42
      }

      param_value2 = %ParameterValue{
        type: ParameterType.parameter_integer(),
        integer_value: 43
      }

      assert not ParameterHelpers.parameter_values_equal?(param_value1, param_value2)
    end

    test "compares array values correctly" do
      # Equal arrays
      param_value1 = %ParameterValue{
        type: ParameterType.parameter_integer_array(),
        integer_array_value: [1, 2, 3]
      }

      param_value2 = %ParameterValue{
        type: ParameterType.parameter_integer_array(),
        integer_array_value: [1, 2, 3]
      }

      assert ParameterHelpers.parameter_values_equal?(param_value1, param_value2)

      # Different arrays
      param_value3 = %ParameterValue{
        type: ParameterType.parameter_integer_array(),
        integer_array_value: [1, 2, 4]
      }

      assert not ParameterHelpers.parameter_values_equal?(param_value1, param_value3)
    end

    test "handles not_set parameters" do
      param_value1 = %ParameterValue{
        type: ParameterType.parameter_not_set()
      }

      param_value2 = %ParameterValue{
        type: ParameterType.parameter_not_set()
      }

      assert ParameterHelpers.parameter_values_equal?(param_value1, param_value2)
    end
  end

  describe "parameters_equal?/2" do
    test "returns true for identical parameters" do
      param1 = %ParameterMsg{
        name: "test_param",
        value: %ParameterValue{
          type: ParameterType.parameter_integer(),
          integer_value: 42
        }
      }

      param2 = %ParameterMsg{
        name: "test_param",
        value: %ParameterValue{
          type: ParameterType.parameter_integer(),
          integer_value: 42
        }
      }

      assert ParameterHelpers.parameters_equal?(param1, param2)
    end

    test "returns false for different names" do
      param1 = %ParameterMsg{
        name: "param1",
        value: %ParameterValue{
          type: ParameterType.parameter_integer(),
          integer_value: 42
        }
      }

      param2 = %ParameterMsg{
        name: "param2",
        value: %ParameterValue{
          type: ParameterType.parameter_integer(),
          integer_value: 42
        }
      }

      assert not ParameterHelpers.parameters_equal?(param1, param2)
    end

    test "returns false for different values" do
      param1 = %ParameterMsg{
        name: "test_param",
        value: %ParameterValue{
          type: ParameterType.parameter_integer(),
          integer_value: 42
        }
      }

      param2 = %ParameterMsg{
        name: "test_param",
        value: %ParameterValue{
          type: ParameterType.parameter_integer(),
          integer_value: 43
        }
      }

      assert not ParameterHelpers.parameters_equal?(param1, param2)
    end
  end

  describe "response struct generation functions" do
    test "gen_get_parameters_response_struct/1" do
      param_values = [
        ParameterHelpers.gen_parameter_value_struct(42),
        ParameterHelpers.gen_parameter_value_struct("hello")
      ]

      response = ParameterHelpers.gen_get_parameters_response_struct(param_values)

      assert response.values == param_values
    end

    test "gen_set_parameters_response_struct/1" do
      results = [
        ParameterHelpers.gen_set_parameters_result_struct(true, "Success"),
        ParameterHelpers.gen_set_parameters_result_struct(false, "Failed")
      ]

      response = ParameterHelpers.gen_set_parameters_response_struct(results)

      assert response.results == results
    end

    test "gen_set_parameters_atomically_response_struct/2" do
      response =
        ParameterHelpers.gen_set_parameters_atomically_response_struct(true, "All parameters set")

      assert response.result.successful == true
      assert response.result.reason == "All parameters set"
    end

    test "gen_list_parameters_response_struct/2" do
      names = ["param1", "param2"]
      prefixes = ["group1", "group2"]

      response = ParameterHelpers.gen_list_parameters_response_struct(names, prefixes)

      assert response.result.names == names
      assert response.result.prefixes == prefixes
    end

    test "gen_describe_parameters_response_struct/1" do
      descriptors = [
        ParameterHelpers.gen_parameter_descriptor_struct("param1"),
        ParameterHelpers.gen_parameter_descriptor_struct("param2")
      ]

      response = ParameterHelpers.gen_describe_parameters_response_struct(descriptors)

      assert response.descriptors == descriptors
    end

    test "gen_get_parameter_types_response_struct/1" do
      # ROS2 type constants
      types = [1, 2, 3]

      response = ParameterHelpers.gen_get_parameter_types_response_struct(types)

      assert response.types == types
    end
  end

  describe "edge cases and error handling" do
    test "handles nil values gracefully" do
      param =
        ParameterHelpers.gen_parameter_struct(
          "nil_param",
          ParameterHelpers.gen_parameter_value_struct(nil)
        )

      assert param.value.type == ParameterType.parameter_not_set()
    end

    test "handles empty strings" do
      param =
        ParameterHelpers.gen_parameter_struct("", ParameterHelpers.gen_parameter_value_struct(""))

      assert param.value.type == ParameterType.parameter_string()
      assert param.name == ""
      assert param.value.string_value == ""
    end

    test "handles very large numbers" do
      large_int = 9_223_372_036_854_775_807

      param =
        ParameterHelpers.gen_parameter_struct(
          "large",
          ParameterHelpers.gen_parameter_value_struct(large_int)
        )

      assert param.value.integer_value == large_int

      large_float = 1.0e100

      param =
        ParameterHelpers.gen_parameter_struct(
          "large_float",
          ParameterHelpers.gen_parameter_value_struct(large_float)
        )

      assert param.value.double_value == large_float
    end

    test "handles unicode strings" do
      unicode = "Hello 世界! 🌍"

      param =
        ParameterHelpers.gen_parameter_struct(
          "unicode",
          ParameterHelpers.gen_parameter_value_struct(unicode)
        )

      assert param.value.string_value == unicode
    end
  end

  describe "integration with ROS2 message structs" do
    test "parameter structs are valid ROS2 message structs" do
      param = ParameterHelpers.gen_parameter_struct("test", true)

      # Should be a valid ParameterMsg struct
      assert match?(%ParameterMsg{}, param)
      assert param.__struct__ == ParameterMsg
    end

    test "parameter value structs are valid ROS2 message structs" do
      param_value = ParameterHelpers.gen_parameter_value_struct(42)

      # Should be a valid ParameterValue struct
      assert match?(%ParameterValue{}, param_value)
      assert param_value.__struct__ == ParameterValue
    end

    test "parameter descriptor structs are valid ROS2 message structs" do
      descriptor = ParameterHelpers.gen_parameter_descriptor_struct("test")

      # Should be a valid ParameterDescriptor struct
      assert match?(%ParameterDescriptor{}, descriptor)
      assert descriptor.__struct__ == ParameterDescriptor
    end

    test "parameter event structs are valid ROS2 message structs" do
      event =
        ParameterHelpers.gen_parameter_event_struct(
          "/node",
          %Time{sec: 1_234_567_890, nanosec: 123_456_789},
          [],
          [],
          []
        )

      # Should be a valid ParameterEvent struct
      assert match?(%ParameterEvent{}, event)
      assert event.__struct__ == ParameterEvent
    end

    test "set parameters result structs are valid ROS2 message structs" do
      result = ParameterHelpers.gen_set_parameters_result_struct(true, "Success")

      # Should be a valid SetParametersResult struct
      assert result.__struct__ == SetParametersResult
    end
  end
end
