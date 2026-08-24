defmodule Rclex.Generators.TypeHashTest do
  use ExUnit.Case

  alias Rclex.Generators.TypeHash

  @share_path "/opt/ros/jazzy/share"

  test "reads the canonical hash for a message" do
    assert {:ok, "RIHS01_df668c740482bbd48fb39d76a70dfd4bd59db1288021743503259e948f6b1a18"} =
             TypeHash.type_hash("std_msgs/msg/String", @share_path)
  end

  test "reads the canonical hash for a service root type" do
    assert {:ok, hash} = TypeHash.type_hash("turtlesim/srv/Kill", @share_path)
    assert String.starts_with?(hash, "RIHS01_")
  end

  test "reads the canonical hash for an action root type" do
    assert {:ok, hash} =
             TypeHash.type_hash("action_tutorials_interfaces/action/Fibonacci", @share_path)

    assert String.starts_with?(hash, "RIHS01_")
  end

  test "returns an error when the type description file is missing" do
    assert {:error, :not_found} = TypeHash.type_hash("missing_msgs/msg/Unknown", @share_path)
  end
end
