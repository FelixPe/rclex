defmodule Rclex.Pkgs.Turtlesim.Action.RotateAbsolute.SendGoal.Request do
  @moduledoc false
  @behaviour Rclex.MessageBehaviour

  defstruct goal_id: %Rclex.Pkgs.UniqueIdentifierMsgs.Msg.UUID{},
            goal: %Rclex.Pkgs.Turtlesim.Action.RotateAbsolute.Goal{}

  @type t :: %__MODULE__{
          goal_id: %Rclex.Pkgs.UniqueIdentifierMsgs.Msg.UUID{},
          goal: %Rclex.Pkgs.Turtlesim.Action.RotateAbsolute.Goal{}
        }

  alias Rclex.Nif

  def type_support!() do
    Nif.turtlesim_action_rotate_absolute__send_goal__request_type_support!()
  end

  def create!() do
    Nif.turtlesim_action_rotate_absolute__send_goal__request_create!()
  end

  def destroy!(message) do
    Nif.turtlesim_action_rotate_absolute__send_goal__request_destroy!(message)
  end

  def set!(message, %__MODULE__{} = struct) do
    Nif.turtlesim_action_rotate_absolute__send_goal__request_set!(message, to_tuple(struct))
  end

  def get!(message) do
    Nif.turtlesim_action_rotate_absolute__send_goal__request_get!(message) |> to_struct()
  end

  def to_tuple(%__MODULE__{goal_id: goal_id, goal: goal}) do
    {Rclex.Pkgs.UniqueIdentifierMsgs.Msg.UUID.to_tuple(goal_id),
     Rclex.Pkgs.Turtlesim.Action.RotateAbsolute.Goal.to_tuple(goal)}
  end

  def to_struct({goal_id, goal}) do
    %__MODULE__{
      goal_id: Rclex.Pkgs.UniqueIdentifierMsgs.Msg.UUID.to_struct(goal_id),
      goal: Rclex.Pkgs.Turtlesim.Action.RotateAbsolute.Goal.to_struct(goal)
    }
  end
end
