defmodule Rclex.Generators.TypeHashTest do
  use ExUnit.Case

  alias Rclex.Generators.TypeHash

  @share_path "/opt/ros/jazzy/share"

  test "reads the canonical hash for a message" do
    assert {:ok, "RIHS01_df668c740482bbd48fb39d76a70dfd4bd59db1288021743503259e948f6b1a18"} =
             TypeHash.type_hash("std_msgs/msg/String", @share_path)
  end

  test "type_hash!/2 returns the canonical hash" do
    assert TypeHash.type_hash!("std_msgs/msg/String", @share_path) ==
             "RIHS01_df668c740482bbd48fb39d76a70dfd4bd59db1288021743503259e948f6b1a18"
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

  test "returns an error when the type name format is invalid" do
    assert {:error, :invalid_type_name} = TypeHash.type_hash("std_msgs/String", @share_path)
  end

  test "type_hash!/2 raises when the type description file is missing" do
    assert_raise ArgumentError, ~r/failed to read type hash: :not_found/, fn ->
      TypeHash.type_hash!("missing_msgs/msg/Unknown", @share_path)
    end
  end

  test "returns an error when type_hashes is missing from the description" do
    share_path = write_description!("custom_msgs/msg/MissingHashes", %{"other" => []})

    assert {:error, :missing_type_hashes} =
             TypeHash.type_hash("custom_msgs/msg/MissingHashes", share_path)
  end

  test "returns an error when the matching hash entry has no hash_string" do
    share_path =
      write_description!("custom_msgs/msg/InvalidHash", %{
        "type_hashes" => [%{"type_name" => "custom_msgs/msg/InvalidHash"}]
      })

    assert {:error, :invalid_type_hash} =
             TypeHash.type_hash("custom_msgs/msg/InvalidHash", share_path)
  end

  defp write_description!(type_name, document) do
    [package, kind, name] = String.split(type_name, "/")
    share_path = Path.join(System.tmp_dir!(), "rclex_type_hash_test_#{System.unique_integer()}")
    dir = Path.join([share_path, package, kind])

    File.mkdir_p!(dir)
    File.write!(Path.join(dir, "#{name}.json"), Jason.encode!(document))

    share_path
  end
end
