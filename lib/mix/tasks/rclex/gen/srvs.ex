defmodule Mix.Tasks.Rclex.Gen.Srvs do
  @shortdoc "Generate codes of ROS 2 srv type"
  @moduledoc """
  #{@shortdoc}

  Before generating, specify msg types in config.exs is needed.

  ```
  config :rclex, ros2_service_types: ["std_srvs/srv/SetBool"]
  ```

  > #### Info {: .info }
  > Be careful, ros2 srv type is case sensitive.

  ## How to show service types

  ```
  mix rclex.gen.srvs --show-types
  ```

  ## How to generate

  ```
  mix rclex.gen.srvs
  ```

  ## How to clean

  ```
  mix rclex.gen.srvs --clean
  ```
  """

  use Mix.Task

  alias Rclex.Parsers.MessageParser
  alias Rclex.Generators.SrvEx
  alias Rclex.Generators.SrvH
  alias Rclex.Generators.SrvC
  alias Rclex.Generators.Util

  @doc false
  def run(args) do
    {valid_options, _, _} =
      OptionParser.parse(args, strict: [clean: :boolean, show_types: :boolean])

    case valid_options do
      [] ->
        clean()
        generate(rclex_dir_path!())
        recompile!()

      [clean: true] ->
        clean()

      [show_types: true] ->
        show_types()

      _ ->
        Mix.shell().info(@moduledoc)
    end
  end

  @doc false
  def generate(to) when is_binary(to) do
    srv_types = Application.get_env(:rclex, :ros2_service_types, [])

    if Enum.empty?(srv_types) do
      Mix.raise("ros2_service_types is not specified in config.")
    end

    for type <- srv_types do
      [interfaces, "srv", type_name] = String.split(type, "/")
      type_name = Util.to_down_snake(type_name)

      dir_path_ex = Path.join(to, "lib/rclex/pkgs/#{interfaces}/srv")
      dir_path_c = Path.join(to, "src/pkgs/#{interfaces}/srv")

      File.mkdir_p!(dir_path_ex)
      File.mkdir_p!(dir_path_c)

      for {dir_path, file_name, binary} <- [
            {dir_path_ex, "#{type_name}.ex", SrvEx.generate(type)},
            {dir_path_c, "#{type_name}.h", SrvH.generate(type)},
            {dir_path_c, "#{type_name}.c", SrvC.generate(type)}
          ] do
        File.write!(Path.join(dir_path, file_name), binary)
      end
    end

    File.write!(Path.join(to, "lib/rclex/srv_funcs.ex"), generate_srv_funcs_ex(srv_types))
    File.write!(Path.join(to, "src/srv_funcs.h"), generate_srv_funcs_h(srv_types))
    File.write!(Path.join(to, "src/srv_funcs.ec"), generate_srv_funcs_c(srv_types))
  end

  @doc false
  def clean() do
    dir_path = rclex_dir_path!()

    file_pathes = Enum.reject(Path.wildcard("lib/rclex/pkgs/*/srv/*.ex") ++ Path.wildcard("src/pkgs/*/srv/*.{c,h}"), fn f -> String.ends_with?(f, "___request.h") or String.ends_with?(f, "___request.c") or  String.ends_with?(f, "___response.h") or String.ends_with?(f, "___response.c") end)
    IO.inspect(file_pathes)
    for file_path <- file_pathes do
      File.rm!(Path.join(dir_path, file_path))
    end

    for file_path <- ["lib/rclex/srv_funcs.ex", "src/srv_funcs.h", "src/srv_funcs.ec"] do
      File.rm_rf!(Path.join(dir_path, file_path))
    end
  end

  @doc false
  def show_types() do
    types = Application.get_env(:rclex, :ros2_service_types, [])

    if Enum.empty?(types) do
      Mix.raise("ros2_service_types is not specified in config.")
    end

    Mix.shell().info(Enum.join(types, " "))
  end

  @doc false
  def generate_srv_funcs_c(types) do
    Enum.map_join(types, fn type ->
      function_prefix = Util.type_down_snake(type)

      """
      {"#{function_prefix}_type_support!", 0, nif_#{function_prefix}_type_support, ERL_NIF_DIRTY_JOB_IO_BOUND},
      """
    end)
  end

  @doc false
  def generate_srv_funcs_ex(types) do
    suffix_args_list = [
      {"type_support!", ""}
    ]

    srv_funcs =
      for type <- types, {suffix, args} <- suffix_args_list do
        prefix = Util.type_down_snake(type)

        """
        def #{prefix}_#{suffix}(#{args}) do
          :erlang.nif_error(:nif_not_loaded)
        end
        """
      end
      |> Enum.join("\n")
      |> String.replace_suffix("\n", "")
      |> String.split("\n")
      |> Enum.map_join("\n", &Kernel.<>(String.duplicate(" ", 6), &1))

    EEx.eval_file(Path.join(Util.templates_dir_path("srv"), "srv_funcs.eex"),
      srv_funcs: srv_funcs
    )
  end


  @doc false
  def generate_srv_funcs_h(types) do
    Enum.map_join(types, fn type ->
      [interfaces, "srv", type] = String.split(type, "/")
      file_path = Path.join([interfaces, "srv", Util.to_down_snake(type)]) <> ".h"

      """
      #include "pkgs/#{file_path}"
      """
    end)
  end



  @doc false
  def get_ros2_message_type_map(ros2_message_type, from, acc \\ %{}) do
    dir = Enum.find(from, fn dir -> File.exists?(Path.join(dir, [ros2_message_type, ".msg"])) end)

    unless dir do
      raise "#{ros2_message_type}.msg not found"
    end

    {:ok, fields, _rest, _context, _line, _column} =
      Path.join(dir, [ros2_message_type, ".msg"])
      |> File.read!()
      |> MessageParser.parse()

    fields = to_complete_fields(fields, ros2_message_type)
    type_map = Map.put(acc, {:msg_type, ros2_message_type}, fields)

    Enum.reduce(fields, type_map, fn [head | _], acc ->
      case head do
        {:builtin_type, _type} ->
          acc

        {:builtin_type_array, _type} ->
          acc

        {:msg_type, type} ->
          get_ros2_message_type_map(type, from, acc)

        {:msg_type_array, type} ->
          get_ros2_message_type_map(get_array_type(type), from, acc)
      end
    end)
  end

  defp rclex_dir_path!() do
    if Mix.Project.config()[:app] == :rclex do
      File.cwd!()
    else
      Path.join(File.cwd!(), "deps/rclex")
    end
  end

  defp recompile!() do
    if Mix.Project.config()[:app] == :rclex do
      Mix.Task.rerun("compile.elixir_make")
    else
      Mix.Task.rerun("deps.compile", ["rclex", "--force"])
    end
  end

  defp to_complete_fields(fields, ros2_message_type) do
    Enum.map(fields, fn field ->
      [head | tail] = field

      case head do
        {:msg_type, type} ->
          type = to_complete_type(type, ros2_message_type)
          [{:msg_type, type} | tail]

        {:msg_type_array, type} ->
          type = to_complete_type(type, ros2_message_type)
          [{:msg_type_array, type} | tail]

        _ ->
          field
      end
    end)
  end

  defp to_complete_type(type, ros2_message_type) do
    if String.contains?(type, "/") do
      [interfaces, type] = String.split(type, "/")
      [interfaces, "srv", type]
    else
      [interfaces, "srv", _] = String.split(ros2_message_type, "/")
      [interfaces, "srv", type]
    end
    |> Path.join()
  end

  defp get_array_type(type) do
    String.replace(type, ~r/\[.*\]$/, "")
  end
end
