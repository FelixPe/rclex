defmodule Rclex.Pkgs.Turtlesim.Action.RotateAbsolute.Goal do
  @moduledoc false
  @behaviour Rclex.MessageBehaviour

  defstruct theta: 0.0

  @type t :: %__MODULE__{theta: float()}

  alias Rclex.Nif

  def type_support!() do
    Nif.turtlesim_action_rotate_absolute__goal_type_support!()
  end

  def create!() do
    Nif.turtlesim_action_rotate_absolute__goal_create!()
  end

  def destroy!(message) do
    Nif.turtlesim_action_rotate_absolute__goal_destroy!(message)
  end

  def set!(message, %__MODULE__{} = struct) do
    Nif.turtlesim_action_rotate_absolute__goal_set!(message, to_tuple(struct))
  end

  def get!(message) do
    Nif.turtlesim_action_rotate_absolute__goal_get!(message) |> to_struct()
  end

  def to_tuple(%__MODULE__{theta: theta}) do
    {theta}
  end

  def to_struct({theta}) do
    %__MODULE__{theta: theta}
  end
end
