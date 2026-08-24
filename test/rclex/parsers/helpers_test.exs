defmodule Rclex.Parsers.HelpersTest do
  use ExUnit.Case, async: true

  import NimbleParsec

  defparsec(:parse_type, Rclex.Parsers.Helpers.parse_type())
  defparsec(:parse_message, Rclex.Parsers.Helpers.parse_message())
  defparsec(:parse_constant, Rclex.Parsers.Helpers.parse_constant())

  test "parse_type/1 builds a combinator for ROS field types" do
    assert {:ok, ["std_msgs/msg/String", "[]"], "", _, _, _} = parse_type("std_msgs/msg/String[]")
  end

  test "parse_message/1 builds a combinator that ignores comments and empty lines" do
    message = "# comment\n\nstring data\n"

    assert {:ok, [[], [], [{:builtin_type, "string"}, "data"]], "", _, _, _} =
             parse_message(message)
  end

  test "parse_constant/1 builds a combinator that ignores fields, comments, and empty lines" do
    constants = "string data\n# comment\n\nuint8 OK=1\n"

    assert {:ok, [[], [], [], [{:builtin_type, "uint8"}, "OK", "=", 1]], "", _, _, _} =
             parse_constant(constants)
  end
end
