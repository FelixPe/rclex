defmodule Rclex.Generators.ActionEx do
  @moduledoc false

  alias Rclex.Generators.Util

  def generate(type) do
    EEx.eval_file(Path.join(Util.templates_dir_path(:action), "action_ex.eex"),
      module_name: module_name(type),
      function_prefix: Util.type_down_snake(type)
    )
  end

  @doc """
  iex> Rclex.Generators.SrvEx.module_name("turtlesim/action/RotateAbsolute")
  "Turtlesim.Action.RotateAbsolute"
  """
  def module_name(ros2_service_type) do
    [pkg, interface_type, type] = String.split(ros2_service_type, "/")

    pkg =
      pkg
      |> String.replace("/", "_")
      |> String.split("_")
      |> Enum.map_join(&String.capitalize(&1))

    Enum.join([pkg, String.capitalize(interface_type), type], ".")
  end
end
