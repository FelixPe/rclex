defmodule Rclex.Urdf.Kinematics do
  @moduledoc false
  alias Rclex.Urdf.Model

  def transforms(%Model{} = model, positions, stamp, opts \\ []) do
    prefix = Keyword.get(opts, :frame_prefix, "")

    with :ok <- validate_stamp(stamp),
         :ok <- validate_positions(positions),
         :ok <- validate_prefix(prefix),
         :ok <- supported(model) do
      result =
        Enum.reduce(
          model.joint_order,
          %{static: [], dynamic: []},
          &append_joint(&1, &2, model, positions, stamp, prefix)
        )

      {:ok, Map.new(result, fn {kind, transforms} -> {kind, Enum.reverse(transforms)} end)}
    end
  rescue
    ArithmeticError -> {:error, :numeric_overflow}
  end

  defp append_joint(name, acc, model, positions, stamp, prefix) do
    joint = Map.fetch!(model.joints, name)

    case position(joint, positions, model.joints) do
      :missing ->
        acc

      {:ok, value} ->
        kind = if joint.type == :fixed, do: :static, else: :dynamic
        transform = stamped(joint, value, stamp, prefix)
        Map.update!(acc, kind, &[transform | &1])
    end
  end

  def validate_stamp(%{sec: sec, nanosec: nanosec})
      when is_integer(sec) and sec >= 0 and sec <= 2_147_483_647 and
             is_integer(nanosec) and nanosec >= 0 and nanosec < 1_000_000_000,
      do: :ok

  def validate_stamp(_), do: {:error, :invalid_timestamp}

  defp validate_positions(positions) when is_map(positions) do
    if Enum.all?(positions, fn {name, position} -> is_binary(name) and is_number(position) end),
      do: :ok,
      else: {:error, :invalid_positions}
  end

  defp validate_positions(_), do: {:error, :invalid_positions}

  defp validate_prefix(prefix) when is_binary(prefix) do
    if not String.starts_with?(prefix, "/") and not Regex.match?(~r/\s/, prefix),
      do: :ok,
      else: {:error, :invalid_frame_prefix}
  end

  defp validate_prefix(_), do: {:error, :invalid_frame_prefix}

  defp supported(model) do
    case Enum.find(
           model.joint_order,
           &(model.joints[&1].type not in [:fixed, :revolute, :continuous, :prismatic])
         ) do
      nil -> :ok
      name -> {:error, {:unsupported_joint, name, model.joints[name].type}}
    end
  end

  defp position(%{type: :fixed}, _positions, _joints), do: {:ok, 0.0}

  defp position(%{mimic: nil, name: name}, positions, _joints) do
    case Map.fetch(positions, name) do
      {:ok, value} -> {:ok, value}
      :error -> :missing
    end
  end

  defp position(%{mimic: mimic}, positions, joints) do
    case position(Map.fetch!(joints, mimic.joint), positions, joints) do
      {:ok, source} -> {:ok, source * mimic.multiplier + mimic.offset}
      :missing -> :missing
    end
  end

  defp stamped(joint, position, stamp, prefix) do
    rotation = rpy(joint.origin.rpy)
    {translation, motion} = motion(joint.type, joint.axis, position)
    {origin_x, origin_y, origin_z} = joint.origin.xyz
    {motion_x, motion_y, motion_z} = rotate(rotation, translation)
    {rotation_x, rotation_y, rotation_z, rotation_w} = multiply(rotation, motion)

    %{
      header: %{frame_id: prefix <> joint.parent, stamp: stamp},
      child_frame_id: prefix <> joint.child,
      transform: %{
        translation: %{x: origin_x + motion_x, y: origin_y + motion_y, z: origin_z + motion_z},
        rotation: %{x: rotation_x, y: rotation_y, z: rotation_z, w: rotation_w}
      }
    }
  end

  defp motion(type, {axis_x, axis_y, axis_z}, position) when type in [:revolute, :continuous] do
    sine = :math.sin(position / 2)
    {{0.0, 0.0, 0.0}, {axis_x * sine, axis_y * sine, axis_z * sine, :math.cos(position / 2)}}
  end

  defp motion(:prismatic, {axis_x, axis_y, axis_z}, position),
    do: {{axis_x * position, axis_y * position, axis_z * position}, {0.0, 0.0, 0.0, 1.0}}

  defp motion(:fixed, _axis, _position), do: {{0.0, 0.0, 0.0}, {0.0, 0.0, 0.0, 1.0}}

  defp rpy({roll, pitch, yaw}) do
    roll_q = {:math.sin(roll / 2), 0.0, 0.0, :math.cos(roll / 2)}
    pitch_q = {0.0, :math.sin(pitch / 2), 0.0, :math.cos(pitch / 2)}
    yaw_q = {0.0, 0.0, :math.sin(yaw / 2), :math.cos(yaw / 2)}
    multiply(multiply(yaw_q, pitch_q), roll_q)
  end

  defp multiply({left_x, left_y, left_z, left_w}, {right_x, right_y, right_z, right_w}) do
    {left_w * right_x + left_x * right_w + left_y * right_z - left_z * right_y,
     left_w * right_y - left_x * right_z + left_y * right_w + left_z * right_x,
     left_w * right_z + left_x * right_y - left_y * right_x + left_z * right_w,
     left_w * right_w - left_x * right_x - left_y * right_y - left_z * right_z}
  end

  defp rotate(
         {rotation_x, rotation_y, rotation_z, rotation_w} = rotation,
         {vector_x, vector_y, vector_z}
       ) do
    {result_x, result_y, result_z, _} =
      rotation
      |> multiply({vector_x, vector_y, vector_z, 0.0})
      |> multiply({-rotation_x, -rotation_y, -rotation_z, rotation_w})

    {result_x, result_y, result_z}
  end
end
