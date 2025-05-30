defmodule Rclex.Generators.ActionHTest do
  use ExUnit.Case

  alias Rclex.Generators.ActionH
  alias Rclex.Generators.Util

  for ros2_action_type <- [
        "tf2_msgs/action/LookupTransform"
      ] do
    test "generate/2 #{ros2_action_type}" do
      ros2_action_type = unquote(ros2_action_type)

      [interfaces, action, type] = String.split(ros2_action_type, "/")
      type_path = Enum.join([interfaces, action, Util.to_down_snake(type)], "/")

      assert ActionH.generate(ros2_action_type) ==
               File.read!(Path.join(File.cwd!(), "test/expected_files/#{type_path}.h"))
    end
  end
end
