defmodule Rclex.Parameter do
  @moduledoc """
  Utilities for working with ROS 2 parameters.

  This module provides functionality for parameter management including
  parameter types, validation, and conversion utilities.
  """

  import Rclex.ParameterHelpers

  @doc """
  Create a new parameter with the given name and value.
  The type is automatically inferred from the value.
  """
  def new(name, value) do
    param_value = gen_parameter_value_struct(value)
    gen_parameter_struct(name, param_value)
  end

  @doc """
  Create a new parameter with explicit type specification.
  """
  def new(name, value, type) do
    param_value = gen_parameter_value_struct(value, type)
    gen_parameter_struct(name, param_value)
  end

  @doc """
  Get the parameter type from a ParameterValue.
  """
  def parameter_value_type(%{type: type} = _param_value) do
    ros2_to_parameter_type(type)
  end

  @doc """
  Create a parameter descriptor.
  """
  def descriptor(name, type, opts \\ []) do
    gen_parameter_descriptor_struct(
      name,
      type,
      opts
    )
  end
end
