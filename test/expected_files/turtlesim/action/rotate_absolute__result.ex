defmodule Rclex.Pkgs.Turtlesim.Action.RotateAbsolute.Result do
  @moduledoc false
  @behaviour Rclex.MessageBehaviour

  defstruct delta: 0.0

  @type t :: %__MODULE__{delta: float()}

  alias Rclex.Nif

  def type_support!() do
    Nif.turtlesim_action_rotate_absolute__result_type_support!()
  end

  def create!() do
    Nif.turtlesim_action_rotate_absolute__result_create!()
  end

  def destroy!(message) do
    Nif.turtlesim_action_rotate_absolute__result_destroy!(message)
  end

  def set!(message, %__MODULE__{} = struct) do
    Nif.turtlesim_action_rotate_absolute__result_set!(message, to_tuple(struct))
  end

  def get!(message) do
    Nif.turtlesim_action_rotate_absolute__result_get!(message) |> to_struct()
  end

  def to_tuple(%__MODULE__{delta: delta}) do
    {delta}
  end

  def to_struct({delta}) do
    %__MODULE__{delta: delta}
  end
end
