defmodule Rclex.RosArgs do
  @moduledoc false

  @spec node_ros_args(keyword()) :: [String.t()]
  def node_ros_args(opts) when is_list(opts) do
    config_remappings = Application.get_env(:rclex, :ros2_remappings, [])
    config_ros_args = Application.get_env(:rclex, :ros2_ros_args, [])

    runtime_remappings = Keyword.get(opts, :remappings, [])
    runtime_ros_args = Keyword.get(opts, :ros_args, [])

    merged_remappings = merge_remappings(config_remappings, runtime_remappings)
    merged_ros_args = normalize_ros_args(config_ros_args) ++ normalize_ros_args(runtime_ros_args)

    ros_specific_args = remappings_to_ros_args(merged_remappings) ++ merged_ros_args

    if ros_specific_args == [] do
      []
    else
      ["--ros-args" | ros_specific_args]
    end
  end

  defp merge_remappings(config_remappings, runtime_remappings) do
    config_pairs = normalize_remappings(config_remappings)
    runtime_pairs = normalize_remappings(runtime_remappings)

    runtime_sources = runtime_pairs |> Enum.map(&elem(&1, 0)) |> MapSet.new()

    config_without_overridden =
      Enum.reject(config_pairs, fn {source, _target} -> source in runtime_sources end)

    config_without_overridden ++ runtime_pairs
  end

  defp normalize_remappings(remappings) when is_list(remappings) do
    Enum.map(remappings, fn
      {source, target} when is_binary(source) and is_binary(target) ->
        {source, target}

      {source, target} when is_list(source) and is_list(target) ->
        {to_string(source), to_string(target)}

      other ->
        raise ArgumentError,
              "invalid remapping entry #{inspect(other)}. Expected {source, target} as strings/chardata"
    end)
  end

  defp normalize_ros_args(args) when is_list(args) do
    Enum.map(args, fn
      arg when is_binary(arg) -> arg
      arg when is_list(arg) -> to_string(arg)
      arg -> raise ArgumentError, "invalid ros_arg #{inspect(arg)}. Expected string/chardata"
    end)
  end

  defp remappings_to_ros_args(remappings) do
    Enum.flat_map(remappings, fn {source, target} -> ["-r", "#{source}:=#{target}"] end)
  end
end
