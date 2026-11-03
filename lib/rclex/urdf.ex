defmodule Rclex.Urdf do
  @moduledoc """
  Parse robot descriptions independently of ROS transport.

  Inspired by the excellent URDF work in [Beam Bots (BB)](https://github.com/beam-bots/bb)
  by James Harton (@jimsynz), particularly `BB.Urdf.Parser`.

  Names remain strings and numeric values use SI units. Visual, collision and
  inertial metadata is retained; mesh resources are not loaded. Use trusted robot
  descriptions: the XML parser rejects DTDs, but `:xmerl` interns XML tag names.
  Xacro is executable configuration and must also come from a trusted source.
  """

  @doc "Parses expanded URDF XML. Xacro must be expanded explicitly before parsing strings."
  @spec parse_string(String.t()) :: {:ok, Rclex.Urdf.Model.t()} | {:error, term()}
  defdelegate parse_string(xml), to: Rclex.Urdf.Parser

  @doc """
  Loads a URDF or Xacro file.

  `:format` is `:auto` (default, expands `.xacro` files), `:urdf`, or `:xacro`.
  Use `format: :xacro` for macro sources named `.urdf`. Expansion uses the
  official ROS tool, preserving relative includes and the inherited ament
  environment. `:mappings`, `:xacro_executable`, `:env`, `:timeout_ms`, and
  `:max_output_bytes` are forwarded to `Rclex.Urdf.Xacro.expand_file/2`.
  """
  @spec parse_file(Path.t(), keyword()) :: {:ok, Rclex.Urdf.Model.t()} | {:error, term()}
  def parse_file(path, opts \\ []) do
    format =
      case Keyword.get(opts, :format, :auto) do
        :auto -> if String.ends_with?(String.downcase(path), ".xacro"), do: :xacro, else: :urdf
        format -> format
      end

    result =
      case format do
        :urdf -> File.read(path)
        :xacro -> Rclex.Urdf.Xacro.expand_file(path, opts)
        other -> {:error, {:invalid_format, other}}
      end

    with {:ok, xml} <- result, do: parse_string(xml)
  end

  @doc """
  Computes parent-to-child TF-compatible maps from a map of joint names to positions.

  Returns `{:ok, %{static: [...], dynamic: [...]}}`. Missing positions are not
  invented; mimic positions are derived only from source positions in this update.
  `stamp` is `%{sec: integer, nanosec: integer}`. `:frame_prefix` is concatenated
  literally to frame names (use `"robot/"` for a slash-separated prefix).
  """
  @spec transforms(Rclex.Urdf.Model.t(), map(), map(), keyword()) ::
          {:ok, map()} | {:error, term()}
  defdelegate transforms(model, positions, stamp, opts \\ []), to: Rclex.Urdf.Kinematics
end
