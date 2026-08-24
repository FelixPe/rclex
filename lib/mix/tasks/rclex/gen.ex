defmodule Mix.Tasks.Rclex.Gen do
  @shortdoc "Generate codes of ROS 2 types"
  @moduledoc """
  #{@shortdoc}

  Before generating, specifying types for topics, services and actions in config.exs is needed.

  ```
  config :rclex,
  ros2_message_types: [
    "std_msgs/msg/String"
  ],
  ros2_service_types: [
    "std_srvs/srv/SetBool"
  ],
  ros2_action_types: [
    "tf2_msgs/action/LookupTransform"
  ]
  ```

  > #### Info {: .info }
  > Be careful, ros2 types are case sensitive.

  ## How to show message types

  ```
  mix rclex.gen --show-types
  ```

  ## How to generate

  ```
  mix rclex.gen
  ```

  This task assumes that the environment variable `ROS_DISTRO` is set
  and refers to the msg types from `/opt/ros/[ROS_DISTRO]/share`.
  In addition `AMENT_PREFIX_PATH` is considered to find types.

  We can also specify explicitly as follows

  ```
  mix rclex.gen --from /opt/ros/humble/share --from /home/ros/workspace/install
  ```

  or via configuration

  ```
  config :rclex, ros2_directories: ["/home/ros/workspace/install/example_msgs"]
  ```

  ## How to clean

  ```
  mix rclex.gen --clean
  ```
  """

  use Mix.Task
  alias Mix.Tasks.Rclex.Gen.Msgs
  alias Mix.Tasks.Rclex.Gen.Srvs
  alias Mix.Tasks.Rclex.Gen.Action

  @doc false
  def run(args) do
    {valid_options, _, _} =
      OptionParser.parse(args, strict: [clean: :boolean, show_types: :boolean])

    case valid_options do
      [] ->
        Msgs.clean()
        Srvs.clean()
        Action.clean()
        Msgs.generate(rclex_dir_path!())
        Srvs.generate(rclex_dir_path!())
        Action.generate(rclex_dir_path!())
        recompile!()

      [clean: true] ->
        Msgs.clean()
        Srvs.clean()
        Action.clean()

      [show_types: true] ->
        Mix.shell().info("Message types: ")
        Msgs.show_types()
        Mix.shell().info("Service types: ")
        Srvs.show_types()
        Mix.shell().info("Action types: ")
        Action.show_types()

      _ ->
        Mix.shell().info(@moduledoc)
    end
  end

  def recompile!() do
    if Mix.Project.config()[:app] == :rclex do
      Mix.Task.rerun("compile.elixir_make")
    else
      recompile_dependency_in_project!()
    end
  end

  @doc false
  def dependency_compile_args, do: ["rclex"]

  # `Mix.Project.in_project/3` spins up an isolated project context rooted at
  # rclex's own directory, which has no knowledge of the parent project's
  # resolved deps tree. When rclex is fetched as a hex/git dependency there is
  # no nested `deps/rclex/deps/elixir_make`, so `compile.elixir_make` (required
  # by rclex's `compilers:` list) can't be found inside that isolated context.
  # Running `deps.compile` from the parent project instead reuses the parent's
  # already-resolved deps/build paths, so `elixir_make` loads correctly.
  defp recompile_dependency_in_project! do
    # Resolved up front: after `deps.compile` fails, the Mix.Project stack may
    # no longer hold the path we'd need to look this up again, and a `rescue`
    # clause can't see variables bound inside the `try`'s `do` block.
    rclex_dir = safe_rclex_dir_path()

    compile_fun = fn ->
      Mix.Task.reenable("deps.compile")
      Mix.Task.run("deps.compile", ["rclex", "--force"])
    end

    try do
      # In a Livebook/`Mix.install/2` session there is no project pushed on
      # the Mix.Project stack once installation finishes, so `deps.compile`
      # has nothing to work with unless we temporarily restore it.
      if Mix.installed?() do
        Mix.in_install_project(compile_fun)
      else
        compile_fun.()
      end

      :ok
    rescue
      error ->
        Mix.raise(
          "failed to compile Rclex dependency at #{rclex_dir}: #{Exception.message(error)}"
        )
    end
  end

  defp safe_rclex_dir_path do
    rclex_dir_path!()
  rescue
    _ -> "rclex"
  end

  def rclex_dir_path!() do
    cond do
      Mix.Project.config()[:app] == :rclex ->
        File.cwd!()

      path = deps_path_from_project() ->
        path

      path = rclex_dep_path() ->
        path

      path = rclex_loaded_dep_path() ->
        path

      true ->
        Mix.raise("unable to resolve rclex dependency path for code generation")
    end
  end

  defp deps_path_from_project do
    Mix.Project.deps_paths()[:rclex]
  rescue
    _ -> nil
  end

  # Returns the expanded absolute path when rclex is declared as a path dep,
  # nil for hex / git dependencies.
  defp rclex_dep_path do
    Mix.Project.config()
    |> Keyword.get(:deps, [])
    |> Enum.find_value(fn
      {:rclex, opts} when is_list(opts) -> Keyword.get(opts, :path)
      {:rclex, _version, opts} when is_list(opts) -> Keyword.get(opts, :path)
      _ -> nil
    end)
    |> case do
      nil -> nil
      path -> Path.expand(path)
    end
  end

  defp rclex_loaded_dep_path do
    app_dir = rclex_app_dir()

    candidates =
      [
        app_dir && source_dir_from_priv_symlink(app_dir),
        app_dir,
        Path.expand("../../../../deps/rclex", app_dir),
        Path.expand("../../deps/rclex", app_dir)
      ]
      |> Enum.reject(&is_nil/1)

    Enum.find(candidates, fn candidate ->
      File.exists?(Path.join(candidate, "mix.exs"))
    end)
  rescue
    ArgumentError -> nil
  end

  defp rclex_app_dir do
    Application.app_dir(:rclex)
  rescue
    ArgumentError ->
      case :code.lib_dir(:rclex) do
        path when is_list(path) -> List.to_string(path)
        _ -> nil
      end
  end

  defp source_dir_from_priv_symlink(app_dir) do
    app_dir
    |> Path.join("priv")
    |> File.read_link()
    |> case do
      {:ok, target} ->
        target
        |> Path.expand(app_dir)
        |> Path.dirname()

      {:error, _reason} ->
        nil
    end
  end
end
