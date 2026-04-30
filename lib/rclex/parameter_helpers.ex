# credo:disable-for-this-file Credo.Check.Refactor.CyclomaticComplexity
defmodule Rclex.ParameterHelpers do
  @moduledoc """
  Helper functions for working with ROS 2 parameter types that may not be known at compile time.
  Provides functions to generate parameter structs, convert between Elixir values and ROS 2 parameter types.
  """

  @doc """
  Generate a Parameter struct with the given name and value.
  The type is automatically inferred from the value.
  """
  def gen_parameter_struct(name, parameter_value) do
    parameter_struct = struct(Rclex.Pkgs.RclInterfaces.Msg.Parameter)
    %{parameter_struct | name: name, value: parameter_value}
  end

  @doc """
  Generate a ParameterValue struct from an Elixir value.
  The type is automatically inferred.
  """
  def gen_parameter_value_struct(value) when is_boolean(value) do
    parameter_value_struct = struct(Rclex.Pkgs.RclInterfaces.Msg.ParameterValue)

    %{
      parameter_value_struct
      | type: apply(Rclex.Pkgs.RclInterfaces.Msg.ParameterType, :parameter_bool, []),
        bool_value: value
    }
  end

  def gen_parameter_value_struct(value) when is_integer(value) do
    parameter_value_struct = struct(Rclex.Pkgs.RclInterfaces.Msg.ParameterValue)

    %{
      parameter_value_struct
      | type: apply(Rclex.Pkgs.RclInterfaces.Msg.ParameterType, :parameter_integer, []),
        integer_value: value
    }
  end

  def gen_parameter_value_struct(value) when is_float(value) do
    parameter_value_struct = struct(Rclex.Pkgs.RclInterfaces.Msg.ParameterValue)

    %{
      parameter_value_struct
      | type: apply(Rclex.Pkgs.RclInterfaces.Msg.ParameterType, :parameter_double, []),
        double_value: value
    }
  end

  def gen_parameter_value_struct(value) when is_binary(value) do
    parameter_value_struct = struct(Rclex.Pkgs.RclInterfaces.Msg.ParameterValue)

    %{
      parameter_value_struct
      | type: apply(Rclex.Pkgs.RclInterfaces.Msg.ParameterType, :parameter_string, []),
        string_value: value
    }
  end

  def gen_parameter_value_struct(value) when is_list(value) do
    parameter_value_struct = struct(Rclex.Pkgs.RclInterfaces.Msg.ParameterValue)

    case value do
      [] ->
        %{
          parameter_value_struct
          | type: apply(Rclex.Pkgs.RclInterfaces.Msg.ParameterType, :parameter_not_set, [])
        }

      [head | _] when is_integer(head) and head >= 0 and head <= 255 ->
        # Check if all elements are bytes
        if Enum.all?(value, &(is_integer(&1) and &1 >= 0 and &1 <= 255)) do
          %{
            parameter_value_struct
            | type: apply(Rclex.Pkgs.RclInterfaces.Msg.ParameterType, :parameter_byte_array, []),
              byte_array_value: value
          }
        else
          %{
            parameter_value_struct
            | type:
                apply(
                  Rclex.Pkgs.RclInterfaces.Msg.ParameterType,
                  :parameter_integer_array,
                  []
                ),
              integer_array_value: value
          }
        end

      [head | _] when is_boolean(head) ->
        %{
          parameter_value_struct
          | type: apply(Rclex.Pkgs.RclInterfaces.Msg.ParameterType, :parameter_bool_array, []),
            bool_array_value: value
        }

      [head | _] when is_integer(head) ->
        %{
          parameter_value_struct
          | type: apply(Rclex.Pkgs.RclInterfaces.Msg.ParameterType, :parameter_integer_array, []),
            integer_array_value: value
        }

      [head | _] when is_float(head) ->
        %{
          parameter_value_struct
          | type: apply(Rclex.Pkgs.RclInterfaces.Msg.ParameterType, :parameter_double_array, []),
            double_array_value: value
        }

      [head | _] when is_binary(head) ->
        %{
          parameter_value_struct
          | type: apply(Rclex.Pkgs.RclInterfaces.Msg.ParameterType, :parameter_string_array, []),
            string_array_value: value
        }

      _ ->
        %{
          parameter_value_struct
          | type: apply(Rclex.Pkgs.RclInterfaces.Msg.ParameterType, :parameter_not_set, [])
        }
    end
  end

  def gen_parameter_value_struct(value) do
    parameter_value_struct = struct(Rclex.Pkgs.RclInterfaces.Msg.ParameterValue)

    %{
      parameter_value_struct
      | type: apply(Rclex.Pkgs.RclInterfaces.Msg.ParameterType, :parameter_not_set, []),
        string_value: "#{inspect(value)}"
    }
  end

  @doc """
  Generate a ParameterValue struct with explicit type specification.
  """
  def gen_parameter_value_struct(value, type) do
    parameter_value_struct = struct(Rclex.Pkgs.RclInterfaces.Msg.ParameterValue)

    case type do
      :boolean ->
        %{
          parameter_value_struct
          | type: apply(Rclex.Pkgs.RclInterfaces.Msg.ParameterType, :parameter_bool, []),
            bool_value: value == true or value == 1 or value == "true"
        }

      :integer ->
        %{
          parameter_value_struct
          | type: apply(Rclex.Pkgs.RclInterfaces.Msg.ParameterType, :parameter_integer, []),
            integer_value: value
        }

      :float ->
        %{
          parameter_value_struct
          | type: apply(Rclex.Pkgs.RclInterfaces.Msg.ParameterType, :parameter_double, []),
            double_value: value
        }

      :string ->
        %{
          parameter_value_struct
          | type: apply(Rclex.Pkgs.RclInterfaces.Msg.ParameterType, :parameter_string, []),
            string_value: to_string(value)
        }

      :byte_array ->
        %{
          parameter_value_struct
          | type: apply(Rclex.Pkgs.RclInterfaces.Msg.ParameterType, :parameter_byte_array, []),
            byte_array_value: value
        }

      :boolean_array ->
        %{
          parameter_value_struct
          | type: apply(Rclex.Pkgs.RclInterfaces.Msg.ParameterType, :parameter_bool_array, []),
            bool_array_value: Enum.map(value, &(&1 == true or &1 == 1 or &1 == "true"))
        }

      :integer_array ->
        %{
          parameter_value_struct
          | type: apply(Rclex.Pkgs.RclInterfaces.Msg.ParameterType, :parameter_integer_array, []),
            integer_array_value: value
        }

      :float_array ->
        %{
          parameter_value_struct
          | type: apply(Rclex.Pkgs.RclInterfaces.Msg.ParameterType, :parameter_double_array, []),
            double_array_value: value
        }

      :string_array ->
        %{
          parameter_value_struct
          | type: apply(Rclex.Pkgs.RclInterfaces.Msg.ParameterType, :parameter_string_array, []),
            string_array_value: value
        }

      :not_set ->
        %{
          parameter_value_struct
          | type: apply(Rclex.Pkgs.RclInterfaces.Msg.ParameterType, :parameter_not_set, [])
        }

      _ ->
        gen_parameter_value_struct(value)
    end
  end

  @doc """
  Generate a ParameterDescriptor struct with default values.
  """
  def gen_parameter_descriptor_struct(name, type \\ :not_set, opts \\ []) do
    descriptor_struct = struct(Rclex.Pkgs.RclInterfaces.Msg.ParameterDescriptor)
    type_int = parameter_type_to_ros2(type)

    %{
      descriptor_struct
      | name: name,
        type: type_int,
        description: Keyword.get(opts, :description, ""),
        additional_constraints: Keyword.get(opts, :additional_constraints, ""),
        read_only: Keyword.get(opts, :read_only, false),
        dynamic_typing: Keyword.get(opts, :dynamic_typing, false),
        floating_point_range: Keyword.get(opts, :floating_point_range, []),
        integer_range: Keyword.get(opts, :integer_range, [])
    }
  end

  @doc """
  Generate a ParameterEvent struct for parameter changes.
  """
  def gen_parameter_event_struct(
        full_node_name,
        timestamp,
        new_parameters,
        changed_parameters,
        deleted_parameters
      ) do
    event = struct(Rclex.Pkgs.RclInterfaces.Msg.ParameterEvent)

    %{
      event
      | stamp: timestamp,
        node: full_node_name,
        new_parameters: new_parameters,
        changed_parameters: changed_parameters,
        deleted_parameters: deleted_parameters
    }
  end

  @doc """
  Generate a ParameterEventDescriptors struct for parameter changes.
  """
  def gen_parameter_event_descriptors_struct(
        new_parameters,
        changed_parameters,
        deleted_parameters
      ) do
    event_descriptors = struct(Rclex.Pkgs.RclInterfaces.Msg.ParameterEventDescriptors)

    %{
      event_descriptors
      | new_parameters: new_parameters,
        changed_parameters: changed_parameters,
        deleted_parameters: deleted_parameters
    }
  end

  @doc """
  Generate a SetParametersResult struct.
  """
  def gen_set_parameters_result_struct(successful, reason \\ "") do
    result = struct(Rclex.Pkgs.RclInterfaces.Msg.SetParametersResult)
    %{result | successful: successful, reason: reason}
  end

  def gen_get_parameters_response_struct(parameter_values) do
    response = struct(Rclex.Pkgs.RclInterfaces.Srv.GetParameters.Response)
    %{response | values: parameter_values}
  end

  def gen_set_parameters_response_struct(results) do
    response = struct(Rclex.Pkgs.RclInterfaces.Srv.SetParameters.Response)
    %{response | results: results}
  end

  def gen_set_parameters_atomically_response_struct(successful, reason \\ "") do
    response = struct(Rclex.Pkgs.RclInterfaces.Srv.SetParametersAtomically.Response)
    result = struct(Rclex.Pkgs.RclInterfaces.Msg.SetParametersResult)
    %{response | result: %{result | successful: successful, reason: reason}}
  end

  def gen_list_parameters_response_struct(names, prefixes) do
    response = struct(Rclex.Pkgs.RclInterfaces.Srv.ListParameters.Response)
    result_struct = struct(Rclex.Pkgs.RclInterfaces.Msg.ListParametersResult)
    result_struct = %{result_struct | names: names, prefixes: prefixes}
    %{response | result: result_struct}
  end

  def gen_describe_parameters_response_struct(descriptors) do
    response = struct(Rclex.Pkgs.RclInterfaces.Srv.DescribeParameters.Response)
    %{response | descriptors: descriptors}
  end

  def gen_get_parameter_types_response_struct(types) do
    response = struct(Rclex.Pkgs.RclInterfaces.Srv.GetParameterTypes.Response)
    %{response | types: types}
  end

  @doc """
  Convert a parameter type atom to the corresponding ROS 2 parameter type constant.
  """
  @spec parameter_type_to_ros2(atom()) :: integer()
  def parameter_type_to_ros2(type) do
    case type do
      :not_set ->
        apply(Rclex.Pkgs.RclInterfaces.Msg.ParameterType, :parameter_not_set, [])

      :boolean ->
        apply(Rclex.Pkgs.RclInterfaces.Msg.ParameterType, :parameter_bool, [])

      :integer ->
        apply(Rclex.Pkgs.RclInterfaces.Msg.ParameterType, :parameter_integer, [])

      :float ->
        apply(Rclex.Pkgs.RclInterfaces.Msg.ParameterType, :parameter_double, [])

      :string ->
        apply(Rclex.Pkgs.RclInterfaces.Msg.ParameterType, :parameter_string, [])

      :byte_array ->
        apply(Rclex.Pkgs.RclInterfaces.Msg.ParameterType, :parameter_byte_array, [])

      :boolean_array ->
        apply(Rclex.Pkgs.RclInterfaces.Msg.ParameterType, :parameter_bool_array, [])

      :integer_array ->
        apply(Rclex.Pkgs.RclInterfaces.Msg.ParameterType, :parameter_integer_array, [])

      :float_array ->
        apply(Rclex.Pkgs.RclInterfaces.Msg.ParameterType, :parameter_double_array, [])

      :string_array ->
        apply(Rclex.Pkgs.RclInterfaces.Msg.ParameterType, :parameter_string_array, [])

      _ ->
        apply(Rclex.Pkgs.RclInterfaces.Msg.ParameterType, :parameter_not_set, [])
    end
  end

  @doc """
  Convert a ROS 2 parameter type constant to the corresponding atom.
  """
  @spec ros2_to_parameter_type(integer()) :: atom()
  def ros2_to_parameter_type(type) do
    cond do
      type == apply(Rclex.Pkgs.RclInterfaces.Msg.ParameterType, :parameter_not_set, []) ->
        :not_set

      type == apply(Rclex.Pkgs.RclInterfaces.Msg.ParameterType, :parameter_bool, []) ->
        :boolean

      type == apply(Rclex.Pkgs.RclInterfaces.Msg.ParameterType, :parameter_integer, []) ->
        :integer

      type == apply(Rclex.Pkgs.RclInterfaces.Msg.ParameterType, :parameter_double, []) ->
        :float

      type == apply(Rclex.Pkgs.RclInterfaces.Msg.ParameterType, :parameter_string, []) ->
        :string

      type == apply(Rclex.Pkgs.RclInterfaces.Msg.ParameterType, :parameter_byte_array, []) ->
        :byte_array

      type == apply(Rclex.Pkgs.RclInterfaces.Msg.ParameterType, :parameter_bool_array, []) ->
        :boolean_array

      type == apply(Rclex.Pkgs.RclInterfaces.Msg.ParameterType, :parameter_integer_array, []) ->
        :integer_array

      type == apply(Rclex.Pkgs.RclInterfaces.Msg.ParameterType, :parameter_double_array, []) ->
        :float_array

      type == apply(Rclex.Pkgs.RclInterfaces.Msg.ParameterType, :parameter_string_array, []) ->
        :string_array

      true ->
        :not_set
    end
  end

  @doc """
  Extract the Elixir value from a ParameterValue struct.
  """
  def parameter_value_to_elixir(nil) do
    nil
  end

  def parameter_value_to_elixir(%{type: type} = param_value) do
    cond do
      type == apply(Rclex.Pkgs.RclInterfaces.Msg.ParameterType, :parameter_bool, []) ->
        param_value.bool_value

      type == apply(Rclex.Pkgs.RclInterfaces.Msg.ParameterType, :parameter_integer, []) ->
        param_value.integer_value

      type == apply(Rclex.Pkgs.RclInterfaces.Msg.ParameterType, :parameter_double, []) ->
        param_value.double_value

      type == apply(Rclex.Pkgs.RclInterfaces.Msg.ParameterType, :parameter_string, []) ->
        param_value.string_value

      type == apply(Rclex.Pkgs.RclInterfaces.Msg.ParameterType, :parameter_byte_array, []) ->
        param_value.byte_array_value

      type == apply(Rclex.Pkgs.RclInterfaces.Msg.ParameterType, :parameter_bool_array, []) ->
        param_value.bool_array_value

      type == apply(Rclex.Pkgs.RclInterfaces.Msg.ParameterType, :parameter_integer_array, []) ->
        param_value.integer_array_value

      type == apply(Rclex.Pkgs.RclInterfaces.Msg.ParameterType, :parameter_double_array, []) ->
        param_value.double_array_value

      type == apply(Rclex.Pkgs.RclInterfaces.Msg.ParameterType, :parameter_string_array, []) ->
        param_value.string_array_value

      type == apply(Rclex.Pkgs.RclInterfaces.Msg.ParameterType, :parameter_not_set, []) ->
        nil

      true ->
        nil
    end
  end

  @doc """
  Extract the Elixir value from a Parameter struct.
  """
  def parameter_to_elixir(%{name: name, value: value} = _parameter) do
    {name, parameter_value_to_elixir(value)}
  end

  @doc """
  Validate parameter name according to ROS 2 naming conventions.
  """
  @spec valid_parameter_name?(String.t()) :: boolean()
  def valid_parameter_name?(name) when is_binary(name) do
    # Parameter names should start with a letter or underscore
    # and can contain letters, numbers, underscores, and dots
    Regex.match?(~r/^[a-zA-Z_][a-zA-Z0-9_.]*$/, name)
  end

  def valid_parameter_name?(_), do: false

  @doc """
  Check if two ParameterValue structs are equivalent.
  """
  def parameter_values_equal?(%{type: type1} = val1, %{type: type2} = val2) do
    type1 == type2 and
      parameter_value_to_elixir(val1) == parameter_value_to_elixir(val2)
  end

  @doc """
  Check if two Parameter structs are equivalent.
  """
  def parameters_equal?(%{name: name1, value: value1}, %{name: name2, value: value2}) do
    name1 == name2 and
      parameter_values_equal?(value1, value2)
  end
end
