defmodule Rclex.Pkgs.Turtlesim.Action.RotateAbsolute.FeedbackMessage do
  @moduledoc false
  @behaviour Rclex.MessageBehaviour

  defstruct goal_id: %Rclex.Pkgs.UniqueIdentifierMsgs.Msg.UUID{},
            feedback: %Rclex.Pkgs.Turtlesim.Action.RotateAbsolute.Feedback{}

  @type t :: %__MODULE__{
          goal_id: %Rclex.Pkgs.UniqueIdentifierMsgs.Msg.UUID{},
          feedback: %Rclex.Pkgs.Turtlesim.Action.RotateAbsolute.Feedback{}
        }

  alias Rclex.Nif

  def type_support!() do
    Nif.turtlesim_action_rotate_absolute__feedback_message_type_support!()
  end

  def create!() do
    Nif.turtlesim_action_rotate_absolute__feedback_message_create!()
  end

  def destroy!(message) do
    Nif.turtlesim_action_rotate_absolute__feedback_message_destroy!(message)
  end

  def set!(message, %__MODULE__{} = struct) do
    Nif.turtlesim_action_rotate_absolute__feedback_message_set!(message, to_tuple(struct))
  end

  def get!(message) do
    Nif.turtlesim_action_rotate_absolute__feedback_message_get!(message) |> to_struct()
  end

  def to_tuple(%__MODULE__{goal_id: goal_id, feedback: feedback}) do
    {Rclex.Pkgs.UniqueIdentifierMsgs.Msg.UUID.to_tuple(goal_id),
     Rclex.Pkgs.Turtlesim.Action.RotateAbsolute.Feedback.to_tuple(feedback)}
  end

  def to_struct({goal_id, feedback}) do
    %__MODULE__{
      goal_id: Rclex.Pkgs.UniqueIdentifierMsgs.Msg.UUID.to_struct(goal_id),
      feedback: Rclex.Pkgs.Turtlesim.Action.RotateAbsolute.Feedback.to_struct(feedback)
    }
  end
end
