defmodule Rclex.Generators.ActionExTest do
  use ExUnit.Case
  doctest Rclex.Generators.ActionEx

  alias Rclex.Generators.ActionEx
  alias Rclex.Generators.Util

  for ros2_action_type <- [
        "tf2_msgs/action/LookupTransform"
      ] do
    test "generate/2 #{ros2_action_type}" do
      ros2_action_type = unquote(ros2_action_type)

      [interfaces, action, type] = String.split(ros2_action_type, "/")
      type_path = Enum.join([interfaces, action, Util.to_down_snake(type)], "/")

      assert ActionEx.generate(ros2_action_type) ==
               File.read!(Path.join(File.cwd!(), "test/expected_files/#{type_path}.ex"))
    end
  end
end
