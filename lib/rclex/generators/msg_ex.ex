defmodule Rclex.Generators.MsgEx do
  @moduledoc false

  alias Rclex.Generators.Util
  alias Rclex.Parsers.TypeParser

  @ros2_elixir_type_map %{
    "bool" => "boolean()",
    "byte" => "byte()",
    "char" => "-128..127",
    "float32" => "float() | :nan | :infinity | :neg_infinity",
    "float64" => "float() | :nan | :infinity | :neg_infinity",
    "int8" => "-128..127",
    "uint8" => "byte()",
    "int16" => "integer()",
    "uint16" => "non_neg_integer()",
    "int32" => "integer()",
    "uint32" => "non_neg_integer()",
    "int64" => "integer()",
    "uint64" => "non_neg_integer()",
    "string" => "String.t()",
    "wstring" => "String.t()"
  }

  @ros2_elixir_default_map %{
    "bool" => "false",
    "byte" => "0",
    "char" => "0",
    "float32" => "0.0",
    "float64" => "0.0",
    "int8" => "0",
    "uint8" => "0",
    "int16" => "0",
    "uint16" => "0",
    "int32" => "0",
    "uint32" => "0",
    "int64" => "0",
    "uint64" => "0",
    "string" => "\"\"",
    "wstring" => "\"\""
  }

  def generate(type, ros2_message_type_map, ros2_constant_type_map \\ %{}) do
    EEx.eval_file(Path.join(Util.templates_dir_path(), "msg_ex.eex"),
      module_name: Util.module_name(type),
      defstruct_fields: defstruct_fields(type, ros2_message_type_map),
      bounded_string_guards: bounded_string_guards(type, ros2_message_type_map),
      to_tuple_guard: to_tuple_guard(type, ros2_message_type_map),
      type_fields: type_fields(type, ros2_message_type_map),
      constant_fields: constant_fields(type, ros2_constant_type_map),
      function_prefix: Util.type_down_snake(type),
      to_tuple_args_fields: to_tuple_args_fields(type, ros2_message_type_map),
      to_struct_args_fields: to_struct_args_fields(type, ros2_message_type_map),
      to_tuple_return_fields: to_tuple_return_fields(type, ros2_message_type_map),
      to_struct_return_fields: to_struct_return_fields(type, ros2_message_type_map)
    )
    |> Code.format_string!()
    |> IO.iodata_to_binary()
    |> then(&"#{&1}\n")
  end

  defp defstruct_builtin_type_field(type, name) do
    type = builtin_type_base(type)
    "#{name}: #{Map.get(@ros2_elixir_default_map, type, "nil")}"
  end

  defp defstruct_builtin_type_field("float32", name, default) do
    "#{name}: #{inspect(1.0 * default)}"
  end

  defp defstruct_builtin_type_field("float64", name, default) do
    "#{name}: #{inspect(1.0 * default)}"
  end

  defp defstruct_builtin_type_field("bool", name, default) do
    "#{name}: #{default}"
  end

  defp defstruct_builtin_type_field(_type, name, default) do
    "#{name}: #{inspect(default)}"
  end

  defp builtin_type_base("string<=" <> _bound), do: "string"
  defp builtin_type_base(type), do: type

  def bounded_string_guards(ros2_message_type, ros2_message_type_map) do
    ros2_message_type
    |> get_fields(ros2_message_type_map)
    |> Enum.flat_map(fn
      [{:builtin_type, "string<=" <> bound}, name | _rest] ->
        ["defguard is_#{name}(value) when is_binary(value) and byte_size(value) <= #{bound}\n"]

      _field ->
        []
    end)
    |> IO.iodata_to_binary()
  end

  def to_tuple_guard(ros2_message_type, ros2_message_type_map) do
    guards =
      ros2_message_type
      |> get_fields(ros2_message_type_map)
      |> Enum.flat_map(fn
        [{:builtin_type, "string<=" <> _bound}, name | _rest] ->
          ["is_#{name}(#{name})"]

        _field ->
          []
      end)

    case guards do
      [] -> ""
      guards -> " when #{Enum.join(guards, " and ")}"
    end
  end

  def defstruct_fields(ros2_message_type, ros2_message_type_map) do
    fields = get_fields(ros2_message_type, ros2_message_type_map)

    if Enum.empty?(fields) do
      "defstruct []"
    else
      fields
      |> Enum.map_join(",\n", fn field ->
        # credo:disable-for-next-line Credo.Check.Refactor.Nesting
        case field do
          [{:builtin_type, type}, name] ->
            defstruct_builtin_type_field(type, name)

          [{:builtin_type, type}, name, default] ->
            defstruct_builtin_type_field(type, name, default)

          [{:builtin_type_array, "uint8[" <> _}, name] ->
            "#{name}: <<>>"

          [{:builtin_type_array, _type}, name] ->
            "#{name}: []"

          [{:builtin_type_array, _type}, name, default] ->
            "#{name}: #{inspect(default)}"

          [{:msg_type, type}, name] ->
            module_name = Util.module_name(type)
            "#{name}: %Rclex.Pkgs.#{module_name}{}"

          [{:msg_type_array, _type}, name] ->
            "#{name}: []"
        end
      end)
      |> then(&"defstruct #{&1}")
    end
  end

  def constant_fields(ros2_message_type, ros2_constant_type_map) do
    constants = get_constants(ros2_message_type, ros2_constant_type_map)

    Enum.reduce(constants, "", fn [{:builtin_type, type}, name, value], acc ->
      acc <>
        case type do
          "string" ->
            "def #{String.downcase(name)}, do: \"#{value}\"\n"

          _ ->
            """
            def #{String.downcase(name)}, do: #{value}
            defguard is_#{String.downcase(name)}(value) when value == #{value}
            """
        end
    end)
  end

  def type_fields(ros2_message_type, ros2_message_type_map) do
    fields = get_fields(ros2_message_type, ros2_message_type_map)

    if Enum.empty?(fields) do
      "@type t :: %__MODULE__{}"
    else
      fields
      |> Enum.map_join(",\n", fn field ->
        [type_tuple, name | _] = field

        # credo:disable-for-next-line Credo.Check.Refactor.Nesting
        case [type_tuple, name] do
          [{:builtin_type, type}, name] ->
            "#{name}: #{@ros2_elixir_type_map[builtin_type_base(type)]}"

          [{:builtin_type_array, "uint8[" <> _}, name] ->
            "#{name}: binary()"

          [{:builtin_type_array, type}, name] ->
            "#{name}: list(#{@ros2_elixir_type_map[get_array_type(type)]})"

          [{:msg_type, type}, name] ->
            module_name = Util.module_name(type)
            "#{name}: %Rclex.Pkgs.#{module_name}{}"

          [{:msg_type_array, type}, name] ->
            module_name = type |> get_array_type() |> Util.module_name()
            "#{name}: list(%Rclex.Pkgs.#{module_name}{})"
        end
      end)
      |> then(&"@type t :: %__MODULE__{#{&1}}")
    end
  end

  def to_tuple_args_fields(ros2_message_type, ros2_message_type_map) do
    get_fields(ros2_message_type, ros2_message_type_map)
    |> Enum.map_join(", ", fn field ->
      [_type_tuple, name | _] = field
      "#{name}: #{name}"
    end)
  end

  def to_struct_args_fields(ros2_message_type, ros2_message_type_map) do
    get_fields(ros2_message_type, ros2_message_type_map)
    |> Enum.map_join(", ", fn field ->
      [_type_tuple, name | _] = field
      "#{name}"
    end)
  end

  def to_tuple_return_fields(ros2_message_type, ros2_message_type_map) do
    fields = get_fields(ros2_message_type, ros2_message_type_map)

    if Enum.empty?(fields) do
      "{}"
    else
      fields
      |> Enum.map_join(",\n", fn field ->
        [type_tuple, name | _] = field

        # credo:disable-for-next-line Credo.Check.Refactor.Nesting
        case [type_tuple, name] do
          [{:builtin_type, "string" <> _}, name] ->
            "#{name}"

          [{:builtin_type, _type}, name] ->
            "#{name}"

          [{:builtin_type_array, "uint8[" <> _}, name] ->
            "#{name}"

          [{:builtin_type_array, _type}, name] ->
            "#{name}"

          [{:msg_type, type}, name] ->
            module_name = Util.module_name(type)
            "Rclex.Pkgs.#{module_name}.to_tuple(#{name})"

          [{:msg_type_array, type}, name] ->
            module_name = type |> get_array_type() |> Util.module_name()

            """
            for struct <- #{name} do
              Rclex.Pkgs.#{module_name}.to_tuple(struct)
            end
            """
            |> String.replace_suffix("\n", "")
        end
      end)
      |> then(&"{#{&1}}")
    end
  end

  def to_struct_return_fields(ros2_message_type, ros2_message_type_map) do
    fields = get_fields(ros2_message_type, ros2_message_type_map)

    if Enum.empty?(fields) do
      "%__MODULE__{}"
    else
      fields
      |> Enum.map_join(",\n", fn field ->
        [type_tuple, name | _] = field

        # credo:disable-for-next-line Credo.Check.Refactor.Nesting
        case [type_tuple, name] do
          [{:builtin_type, "string" <> _}, name] ->
            "#{name}: #{name}"

          [{:builtin_type, _type}, name] ->
            "#{name}: #{name}"

          [{:builtin_type_array, "uint8[" <> _}, name] ->
            "#{name}: #{name}"

          [{:builtin_type_array, _type}, name] ->
            "#{name}: #{name}"

          [{:msg_type, type}, name] ->
            module_name = Util.module_name(type)
            "#{name}: Rclex.Pkgs.#{module_name}.to_struct(#{name})"

          [{:msg_type_array, type}, name] ->
            module_name = type |> get_array_type() |> Util.module_name()

            """
            #{name}:
              for tuple <- #{name} do
                Rclex.Pkgs.#{module_name}.to_struct(tuple)
              end
            """
            |> String.replace_suffix("\n", "")
        end
      end)
      |> then(&"%__MODULE__{#{&1}}")
    end
  end

  defp get_fields(ros2_message_type, ros2_message_type_map) do
    Map.get(ros2_message_type_map, {:msg_type, ros2_message_type})
  end

  defp get_constants(ros2_message_type, ros2_constant_type_map) do
    Map.get(ros2_constant_type_map, {:msg_type, ros2_message_type}, [])
  end

  defp get_array_type(type) do
    {:ok, acc, _rest, _context, _line, _column} = TypeParser.parse(type)
    [type | _] = acc
    type
  end
end
