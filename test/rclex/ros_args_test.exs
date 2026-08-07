defmodule Rclex.RosArgsTest do
  use ExUnit.Case

  alias Rclex.RosArgs

  setup do
    old_remappings = Application.get_env(:rclex, :ros2_remappings)
    old_ros_args = Application.get_env(:rclex, :ros2_ros_args)

    on_exit(fn ->
      if is_nil(old_remappings) do
        Application.delete_env(:rclex, :ros2_remappings)
      else
        Application.put_env(:rclex, :ros2_remappings, old_remappings)
      end

      if is_nil(old_ros_args) do
        Application.delete_env(:rclex, :ros2_ros_args)
      else
        Application.put_env(:rclex, :ros2_ros_args, old_ros_args)
      end
    end)

    :ok
  end

  test "node_ros_args/1 returns [] when no config and no opts" do
    Application.delete_env(:rclex, :ros2_remappings)
    Application.delete_env(:rclex, :ros2_ros_args)

    assert RosArgs.node_ros_args([]) == []
  end

  test "node_ros_args/1 uses config defaults" do
    Application.put_env(:rclex, :ros2_remappings, [{"/from", "/to"}])
    Application.put_env(:rclex, :ros2_ros_args, ["--log-level", "debug"])

    assert RosArgs.node_ros_args([]) ==
             ["--ros-args", "-r", "/from:=/to", "--log-level", "debug"]
  end

  test "node_ros_args/1 gives runtime remappings precedence over config" do
    Application.put_env(:rclex, :ros2_remappings, [{"/from", "/from_config"}, {"/other", "/other_config"}])

    assert RosArgs.node_ros_args(remappings: [{"/from", "/from_runtime"}]) ==
             ["--ros-args", "-r", "/other:=/other_config", "-r", "/from:=/from_runtime"]
  end

  test "node_ros_args/1 appends runtime ros_args after config ros_args" do
    Application.put_env(:rclex, :ros2_ros_args, ["--log-level", "warn"])

    assert RosArgs.node_ros_args(ros_args: ["--param", "use_sim_time:=true"]) ==
             ["--ros-args", "--log-level", "warn", "--param", "use_sim_time:=true"]
  end
end
