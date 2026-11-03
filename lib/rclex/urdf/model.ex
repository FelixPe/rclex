defmodule Rclex.Urdf.Model do
  @moduledoc "Immutable URDF topology and description metadata. Link and joint names are strings."
  @type t :: %__MODULE__{
          name: String.t(),
          root: String.t(),
          links: map(),
          joints: %{String.t() => Rclex.Urdf.Joint.t()},
          joint_order: [String.t()],
          materials: map(),
          warnings: [String.t()]
        }
  defstruct [:name, :root, links: %{}, joints: %{}, joint_order: [], materials: %{}, warnings: []]
end
