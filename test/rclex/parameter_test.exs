defmodule Rclex.ParameterTest do
  use ExUnit.Case, async: true

  alias Rclex.Parameter
  alias Rclex.Pkgs.RclInterfaces.Msg.ParameterType
  alias Rclex.Pkgs.RclInterfaces.Msg.ParameterValue
  alias Rclex.Pkgs.RclInterfaces.Msg.Parameter, as: ParameterMsg
  alias Rclex.Pkgs.RclInterfaces.Msg.ParameterDescriptor

  doctest Rclex.Parameter

  describe "new/2 with automatic type inference" do
    test "creates boolean parameter" do
      param = Parameter.new("test_bool", true)

      assert param.name == "test_bool"
      assert param.value.type == ParameterType.parameter_bool()
      assert param.value.bool_value == true
      assert param.value.integer_value == 0
      assert param.value.double_value == 0.0
      assert param.value.string_value == ""
    end

    test "creates integer parameter" do
      param = Parameter.new("test_int", 42)

      assert param.name == "test_int"
      assert param.value.type == ParameterType.parameter_integer()
      assert param.value.bool_value == false
      assert param.value.integer_value == 42
      assert param.value.double_value == 0.0
      assert param.value.string_value == ""
    end

    test "creates double parameter" do
      param = Parameter.new("test_double", 3.14)

      assert param.name == "test_double"
      assert param.value.type == ParameterType.parameter_double()
      assert param.value.bool_value == false
      assert param.value.integer_value == 0
      assert param.value.double_value == 3.14
      assert param.value.string_value == ""
    end

    test "creates string parameter" do
      param = Parameter.new("test_string", "hello")

      assert param.name == "test_string"
      assert param.value.type == ParameterType.parameter_string()
      assert param.value.bool_value == false
      assert param.value.integer_value == 0
      assert param.value.double_value == 0.0
      assert param.value.string_value == "hello"
    end

    test "creates byte array parameter" do
      param = Parameter.new("test_bytes", [1, 2, 3, 255])

      assert param.name == "test_bytes"
      assert param.value.type == ParameterType.parameter_byte_array()
      assert param.value.byte_array_value == [1, 2, 3, 255]
      assert param.value.bool_array_value == []
      assert param.value.integer_array_value == []
    end

    test "creates boolean array parameter" do
      param = Parameter.new("test_bool_array", [true, false, true])

      assert param.name == "test_bool_array"
      assert param.value.type == ParameterType.parameter_bool_array()
      assert param.value.bool_array_value == [true, false, true]
      assert param.value.byte_array_value == []
      assert param.value.integer_array_value == []
    end

    test "creates integer array parameter" do
      param = Parameter.new("test_int_array", [1, 2, 3, 300])

      assert param.name == "test_int_array"
      assert param.value.type == ParameterType.parameter_integer_array()
      assert param.value.integer_array_value == [1, 2, 3, 300]
      assert param.value.bool_array_value == []
      assert param.value.double_array_value == []
    end

    test "creates double array parameter" do
      param = Parameter.new("test_double_array", [1.1, 2.2, 3.3])

      assert param.name == "test_double_array"
      assert param.value.type == ParameterType.parameter_double_array()
      assert param.value.double_array_value == [1.1, 2.2, 3.3]
      assert param.value.integer_array_value == []
      assert param.value.string_array_value == []
    end

    test "creates string array parameter" do
      param = Parameter.new("test_string_array", ["hello", "world"])

      assert param.name == "test_string_array"
      assert param.value.type == ParameterType.parameter_string_array()
      assert param.value.string_array_value == ["hello", "world"]
      assert param.value.double_array_value == []
      assert param.value.bool_array_value == []
    end

    test "creates not_set parameter for empty list" do
      param = Parameter.new("test_empty", [])

      assert param.name == "test_empty"
      assert param.value.type == ParameterType.parameter_not_set()
      assert param.value.bool_value == false
      assert param.value.integer_value == 0
    end

    test "creates not_set parameter for nil" do
      param = Parameter.new("test_nil", nil)

      assert param.name == "test_nil"
      assert param.value.type == ParameterType.parameter_not_set()
      assert param.value.bool_value == false
      assert param.value.integer_value == 0
    end

    test "distinguishes between byte array and integer array" do
      # Byte array (all values 0-255)
      byte_param = Parameter.new("bytes", [1, 2, 255])
      assert byte_param.value.type == ParameterType.parameter_byte_array()
      assert byte_param.value.byte_array_value == [1, 2, 255]

      # Integer array (contains values > 255)
      int_param = Parameter.new("ints", [1, 2, 256])
      assert int_param.value.type == ParameterType.parameter_integer_array()
      assert int_param.value.integer_array_value == [1, 2, 256]
    end
  end

  describe "new/3 with explicit type specification" do
    test "creates parameter with explicit bool type" do
      param = Parameter.new("test_bool", 1, :boolean)

      assert param.name == "test_bool"
      assert param.value.type == ParameterType.parameter_bool()
      assert param.value.bool_value == true
    end

    test "creates parameter with explicit integer type" do
      param = Parameter.new("test_int", "42", :integer)

      assert param.name == "test_int"
      assert param.value.type == ParameterType.parameter_integer()
      assert param.value.integer_value == "42"
    end

    test "creates parameter with explicit float type" do
      param = Parameter.new("test_double", 42, :float)

      assert param.name == "test_double"
      assert param.value.type == ParameterType.parameter_double()
      assert param.value.double_value == 42
    end

    test "creates parameter with explicit string type" do
      param = Parameter.new("test_string", 42, :string)

      assert param.name == "test_string"
      assert param.value.type == ParameterType.parameter_string()
      assert param.value.string_value == "42"
    end

    test "creates parameter with explicit byte_array type" do
      param = Parameter.new("test_bytes", [1, 2, 300], :byte_array)

      assert param.name == "test_bytes"
      assert param.value.type == ParameterType.parameter_byte_array()
      assert param.value.byte_array_value == [1, 2, 300]
    end

    test "creates parameter with explicit boolean_array type" do
      param = Parameter.new("test_boolean_array", [1, 0, "true"], :boolean_array)

      assert param.name == "test_boolean_array"
      assert param.value.type == ParameterType.parameter_bool_array()
      assert param.value.bool_array_value == [true, false, true]
    end

    test "creates parameter with explicit integer_array type" do
      param = Parameter.new("test_int_array", [1.1, 2.2], :integer_array)

      assert param.name == "test_int_array"
      assert param.value.type == ParameterType.parameter_integer_array()
      assert param.value.integer_array_value == [1.1, 2.2]
    end

    test "creates parameter with explicit double_array type" do
      param = Parameter.new("test_double_array", [1, 2], :float_array)

      assert param.name == "test_double_array"
      assert param.value.type == ParameterType.parameter_double_array()
      assert param.value.double_array_value == [1, 2]
    end

    test "creates parameter with explicit string_array type" do
      param = Parameter.new("test_string_array", [1, 2], :string_array)

      assert param.name == "test_string_array"
      assert param.value.type == ParameterType.parameter_string_array()
      assert param.value.string_array_value == [1, 2]
    end

    test "creates parameter with explicit not_set type" do
      param = Parameter.new("test_not_set", "any_value", :not_set)

      assert param.name == "test_not_set"
      assert param.value.type == ParameterType.parameter_not_set()
      assert param.value.bool_value == false
      assert param.value.integer_value == 0
    end

    test "falls back to automatic inference for unknown type" do
      param = Parameter.new("test_fallback", 42, :unknown_type)

      assert param.name == "test_fallback"
      assert param.value.type == ParameterType.parameter_integer()
      assert param.value.integer_value == 42
    end
  end

  describe "parameter_value_type/1" do
    test "returns correct type for boolean parameter" do
      param_value = %ParameterValue{
        type: ParameterType.parameter_bool(),
        bool_value: true
      }

      assert Parameter.parameter_value_type(param_value) == :boolean
    end

    test "returns correct type for integer parameter" do
      param_value = %ParameterValue{
        type: ParameterType.parameter_integer(),
        integer_value: 42
      }

      assert Parameter.parameter_value_type(param_value) == :integer
    end

    test "returns correct type for float parameter" do
      param_value = %ParameterValue{
        type: ParameterType.parameter_double(),
        double_value: 3.14
      }

      assert Parameter.parameter_value_type(param_value) == :float
    end

    test "returns correct type for string parameter" do
      param_value = %ParameterValue{
        type: ParameterType.parameter_string(),
        string_value: "hello"
      }

      assert Parameter.parameter_value_type(param_value) == :string
    end

    test "returns correct type for byte_array parameter" do
      param_value = %ParameterValue{
        type: ParameterType.parameter_byte_array(),
        byte_array_value: [1, 2, 3]
      }

      assert Parameter.parameter_value_type(param_value) == :byte_array
    end

    test "returns correct type for bool_array parameter" do
      param_value = %ParameterValue{
        type: ParameterType.parameter_bool_array(),
        bool_array_value: [true, false]
      }

      assert Parameter.parameter_value_type(param_value) == :boolean_array
    end

    test "returns correct type for integer_array parameter" do
      param_value = %ParameterValue{
        type: ParameterType.parameter_integer_array(),
        integer_array_value: [1, 2, 3]
      }

      assert Parameter.parameter_value_type(param_value) == :integer_array
    end

    test "returns correct type for float_array parameter" do
      param_value = %ParameterValue{
        type: ParameterType.parameter_double_array(),
        double_array_value: [1.1, 2.2]
      }

      assert Parameter.parameter_value_type(param_value) == :float_array
    end

    test "returns correct type for string_array parameter" do
      param_value = %ParameterValue{
        type: ParameterType.parameter_string_array(),
        string_array_value: ["hello", "world"]
      }

      assert Parameter.parameter_value_type(param_value) == :string_array
    end

    test "returns not_set for not_set parameter" do
      param_value = %ParameterValue{
        type: ParameterType.parameter_not_set()
      }

      assert Parameter.parameter_value_type(param_value) == :not_set
    end

    test "returns not_set for unknown type" do
      param_value = %ParameterValue{
        # Unknown type
        type: 999
      }

      assert Parameter.parameter_value_type(param_value) == :not_set
    end
  end

  describe "descriptor/2" do
    test "creates basic descriptor with name and type" do
      descriptor = Parameter.descriptor("my_param", :integer)

      assert descriptor.name == "my_param"
      assert descriptor.type == ParameterType.parameter_integer()
      assert descriptor.description == ""
      assert descriptor.additional_constraints == ""
      assert descriptor.read_only == false
      assert descriptor.dynamic_typing == false
    end

    test "creates descriptor with all parameter types" do
      types = [
        :not_set,
        :boolean,
        :integer,
        :float,
        :string,
        :byte_array,
        :boolean_array,
        :integer_array,
        :float_array,
        :string_array
      ]

      expected_type_values = [
        ParameterType.parameter_not_set(),
        ParameterType.parameter_bool(),
        ParameterType.parameter_integer(),
        ParameterType.parameter_double(),
        ParameterType.parameter_string(),
        ParameterType.parameter_byte_array(),
        ParameterType.parameter_bool_array(),
        ParameterType.parameter_integer_array(),
        ParameterType.parameter_double_array(),
        ParameterType.parameter_string_array()
      ]

      Enum.zip(types, expected_type_values)
      |> Enum.each(fn {type_atom, expected_value} ->
        descriptor = Parameter.descriptor("param", type_atom)
        assert descriptor.type == expected_value
      end)
    end
  end

  describe "descriptor/4" do
    test "creates descriptor with description and constraints" do
      descriptor =
        Parameter.descriptor(
          "my_param",
          :float,
          description: "A test parameter",
          additional_constraints: "Must be positive"
        )

      assert descriptor.name == "my_param"
      assert descriptor.type == ParameterType.parameter_double()
      assert descriptor.description == "A test parameter"
      assert descriptor.additional_constraints == "Must be positive"
      assert descriptor.read_only == false
      assert descriptor.dynamic_typing == false
    end

    test "creates descriptor with empty strings for defaults" do
      descriptor = Parameter.descriptor("param", :string)

      assert descriptor.description == ""
      assert descriptor.additional_constraints == ""
    end
  end

  describe "integration with ParameterHelpers functions" do
    test "parameter structs are valid ROS2 message structs" do
      param = Parameter.new("test", true)

      # Should be a valid ParameterMsg struct
      assert match?(%ParameterMsg{}, param)
      assert param.__struct__ == ParameterMsg
    end

    test "parameter value structs are valid ROS2 message structs" do
      param = Parameter.new("test", 42)

      # Should be a valid ParameterValue struct
      assert match?(%ParameterValue{}, param.value)
      assert param.value.__struct__ == ParameterValue
    end

    test "parameter descriptor structs are valid ROS2 message structs" do
      descriptor = Parameter.descriptor("test", :integer)

      # Should be a valid ParameterDescriptor struct
      assert match?(%ParameterDescriptor{}, descriptor)
      assert descriptor.__struct__ == ParameterDescriptor
    end
  end

  describe "edge cases and error handling" do
    test "handles empty parameter name" do
      param = Parameter.new("", 42)
      assert param.name == ""
      assert param.value.integer_value == 42
    end

    test "handles special characters in parameter name" do
      param = Parameter.new("param_with.dots_and-dashes", "test")
      assert param.name == "param_with.dots_and-dashes"
      assert param.value.string_value == "test"
    end

    test "handles large integers" do
      # Max int64
      large_int = 9_223_372_036_854_775_807
      param = Parameter.new("large_int", large_int)
      assert param.value.integer_value == large_int
    end

    test "handles very small floats" do
      small_double = 1.0e-100
      param = Parameter.new("small_double", small_double)
      assert param.value.double_value == small_double
    end

    test "handles very large doubles" do
      large_double = 1.0e100
      param = Parameter.new("large_double", large_double)
      assert param.value.double_value == large_double
    end

    test "handles empty arrays" do
      param = Parameter.new("empty_array", [])
      assert param.value.type == ParameterType.parameter_not_set()
    end

    test "handles nil values gracefully" do
      param = Parameter.new("nil_value", nil)
      assert param.value.type == ParameterType.parameter_not_set()
      assert param.value.bool_value == false
      assert param.value.integer_value == 0
    end

    test "handles unicode strings" do
      unicode_string = "Hello 世界! 🌍"
      param = Parameter.new("unicode", unicode_string)
      assert param.value.string_value == unicode_string
    end

    test "handles very long strings" do
      long_string = String.duplicate("a", 10_000)
      param = Parameter.new("long_string", long_string)
      assert param.value.string_value == long_string
    end

    test "handles mixed array types gracefully" do
      # Mixed array should be treated based on first element
      mixed_array = [1, "string", true]
      param = Parameter.new("mixed", mixed_array)
      # Should be integer array based on first element
      assert param.value.type == ParameterType.parameter_integer_array()
    end

    test "handles string conversion for string type" do
      param = Parameter.new("test", 42, :string)
      assert param.value.type == ParameterType.parameter_string()
      assert param.value.string_value == "42"
    end
  end
end
