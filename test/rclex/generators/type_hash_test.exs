defmodule Rclex.Generators.TypeHashTest do
  use ExUnit.Case

  alias Rclex.Generators.TypeHash

  @share_path "/opt/ros/jazzy/share"

  test "reads the canonical hash for a message" do
    assert {:ok, "RIHS01_df668c740482bbd48fb39d76a70dfd4bd59db1288021743503259e948f6b1a18"} =
             TypeHash.type_hash("std_msgs/msg/String", @share_path)
  end

  test "calculates the canonical hash from a type description struct" do
    {:ok, description} = Rclex.TypeDescriptionRegistry.fetch("std_msgs/msg/String")

    assert {:ok, "RIHS01_df668c740482bbd48fb39d76a70dfd4bd59db1288021743503259e948f6b1a18"} =
             TypeHash.calculate_type_hash(description)
  end

  test "calculated hash matches JSON hash for a nested message type" do
    type_name = "geometry_msgs/msg/Twist"
    {:ok, json_hash} = TypeHash.type_hash(type_name, @share_path)
    {:ok, description} = Rclex.TypeDescriptionRegistry.fetch(type_name)

    assert {:ok, ^json_hash} = TypeHash.calculate_type_hash(description)
  end

  test "reads the canonical hash for a service root type" do
    assert {:ok, hash} = TypeHash.type_hash("turtlesim/srv/Kill", @share_path)
    assert String.starts_with?(hash, "RIHS01_")
  end

  test "reads the canonical hash for an action root type" do
    assert {:ok, hash} = TypeHash.type_hash("tf2_msgs/action/LookupTransform", @share_path)
    assert String.starts_with?(hash, "RIHS01_")
  end

  test "returns an error when the type description file is missing" do
    assert {:error, :not_found} = TypeHash.type_hash("missing_msgs/msg/Unknown", @share_path)
  end
end
