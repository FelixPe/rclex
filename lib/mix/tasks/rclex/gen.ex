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
      case System.cmd("mix", ["deps.compile" | dependency_compile_args()],
             stderr_to_stdout: true,
             into: IO.stream(:stdio, :line)
           ) do
        {_, 0} -> :ok
        {_, status} -> Mix.raise("failed to compile Rclex dependency (exit status #{status})")
      end
    end
  end

  @doc false
  def dependency_compile_args, do: ["rclex"]

  def rclex_dir_path!() do
    cond do
      Mix.Project.config()[:app] == :rclex ->
        File.cwd!()

      path = rclex_dep_path() ->
        path

      true ->
        Path.join(File.cwd!(), "deps/rclex")
    end
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
end
