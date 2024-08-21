defmodule Rclex.Pkgs.Turtlesim.Action.RotateAbsolute.Feedback do
  @moduledoc false
  @behaviour Rclex.MessageBehaviour

  defstruct remaining: 0.0

  @type t :: %__MODULE__{remaining: float()}

  alias Rclex.Nif

  def type_support!() do
    Nif.turtlesim_action_rotate_absolute__feedback_type_support!()
  end

  def create!() do
    Nif.turtlesim_action_rotate_absolute__feedback_create!()
  end

  def destroy!(message) do
    Nif.turtlesim_action_rotate_absolute__feedback_destroy!(message)
  end

  def set!(message, %__MODULE__{} = struct) do
    Nif.turtlesim_action_rotate_absolute__feedback_set!(message, to_tuple(struct))
  end

  def get!(message) do
    Nif.turtlesim_action_rotate_absolute__feedback_get!(message) |> to_struct()
  end

  def to_tuple(%__MODULE__{remaining: remaining}) do
    {remaining}
  end

  def to_struct({remaining}) do
    %__MODULE__{remaining: remaining}
  end
end
