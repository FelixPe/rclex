defmodule Rclex.Urdf.Joint do
  @moduledoc "URDF joint metadata in SI units; origin uses XYZ and fixed-axis roll, pitch, yaw."
  @type t :: %__MODULE__{}
  defstruct [
    :name,
    :type,
    :parent,
    :child,
    :limit,
    :dynamics,
    :mimic,
    origin: %{xyz: {0.0, 0.0, 0.0}, rpy: {0.0, 0.0, 0.0}},
    axis: {1.0, 0.0, 0.0}
  ]
end
