defmodule Rclex.Parsers.ConstantParserTest do
  use ExUnit.Case

  alias Rclex.Parsers.ConstantParser

  # |> optional(whitespace())
  # |> field_type()
  # |> ignore(whitespace())
  # |> ascii_string([?A..?Z, ?_, ?0..?9], min: 1)
  # |> ignore(optional(whitespace()))
  # |> string("=")
  # |> ignore(optional(whitespace()))
  # |> choice([value_float(), value_integer(), value_string()])
  # |> ignore(optional(whitespace()))
  # |> ignore(optional(comment()))
  # |> ignore(new_line())

  for {text, expected} <- [
        {"\n\n# comment\nstring NAME=\"value\"\n\n",
         [[{:builtin_type, "string"}, "NAME", "=", "value"]]},
        {"int32 X=123\n", [[{:builtin_type, "int32"}, "X", "=", 123]]},
        {"int32 Y=-123\n", [[{:builtin_type, "int32"}, "Y", "=", -123]]},
        {"string FOO=\"foo\"\n", [[{:builtin_type, "string"}, "FOO", "=", "foo"]]},
        {"string EXAMPLE='bar'\n", [[{:builtin_type, "string"}, "EXAMPLE", "=", "bar"]]},
        {"int32[] foo\n", []},
        {"int32[5] bar\n", []}
      ] do
    test "#{text}" do
      text = unquote(text)
      expected = unquote(expected)

      {:ok, acc, _rest, _context, _line, _column} = ConstantParser.parse("#{text}")
      assert acc == expected
    end
  end
end
