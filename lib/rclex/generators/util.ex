defmodule Rclex.Generators.Util do
  @moduledoc false

  def templates_dir_path(interface \\ :msg) do
    case interface do
      :msg -> Path.join(Application.app_dir(:rclex), "priv/templates/rclex.gen.msgs")
      :srv -> Path.join(Application.app_dir(:rclex), "priv/templates/rclex.gen.srvs")
      _ -> raise "ros2 interface type not supported"
    end
  end

  @doc """
  iex> Rclex.Generators.Util.type_down_snake("std_msgs/msg/String")
  "std_msgs_msg_string"

  iex> Rclex.Generators.Util.type_down_snake("std_msgs/msg/UInt32MultiArray")
  "std_msgs_msg_u_int32_multi_array"
  """
  def type_down_snake(ros2_message_type) do
    [interfaces, msg, type] = ros2_message_type |> String.split("/")
    [interfaces, msg, to_down_snake(type)] |> Enum.join("_")
  end

  @doc """
  iex> Rclex.Generators.Util.to_down_snake("Vector3")
  "vector3"

  iex> Rclex.Generators.Util.to_down_snake("TwistWithCovariance")
  "twist_with_covariance"

  iex> Rclex.Generators.Util.to_down_snake("UInt32MultiArray")
  "u_int32_multi_array"
  """
  def to_down_snake(type_name) do

    # insert an underscore before any upper case letter
    # which is not followed by another upper case letter
    underscore_before_words = Regex.replace(~r/(.)([A-Z][a-z]+)/, type_name, "\\g{1}_\\g{2}")
    # insert an underscore before any upper case letter
    # which is preseded by a lower case letter or number
    underscore_after_words = Regex.replace(~r/([a-z0-9])([A-Z])/, underscore_before_words, "\\g{1}_\\g{2}")

    String.downcase(underscore_after_words)
  end
end
