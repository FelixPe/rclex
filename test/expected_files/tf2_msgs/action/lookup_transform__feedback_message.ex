defmodule Rclex.Pkgs.Tf2Msgs.Action.LookupTransform.FeedbackMessage do
  @moduledoc false
  @behaviour Rclex.MessageBehaviour

  defstruct goal_id: %Rclex.Pkgs.UniqueIdentifierMsgs.Msg.UUID{},
            feedback: %Rclex.Pkgs.Tf2Msgs.Action.LookupTransform.Feedback{}

  @type t :: %__MODULE__{
          goal_id: %Rclex.Pkgs.UniqueIdentifierMsgs.Msg.UUID{},
          feedback: %Rclex.Pkgs.Tf2Msgs.Action.LookupTransform.Feedback{}
        }

  alias Rclex.Nif

  def type_support!() do
    Nif.tf2_msgs_action_lookup_transform__feedback_message_type_support!()
  end

  def create!() do
    Nif.tf2_msgs_action_lookup_transform__feedback_message_create!()
  end

  def destroy!(message) do
    Nif.tf2_msgs_action_lookup_transform__feedback_message_destroy!(message)
  end

  def set!(message, %__MODULE__{} = struct) do
    Nif.tf2_msgs_action_lookup_transform__feedback_message_set!(message, to_tuple(struct))
  end

  def get!(message) do
    Nif.tf2_msgs_action_lookup_transform__feedback_message_get!(message) |> to_struct()
  end

  def to_tuple(%__MODULE__{goal_id: goal_id, feedback: feedback}) do
    {Rclex.Pkgs.UniqueIdentifierMsgs.Msg.UUID.to_tuple(goal_id),
     Rclex.Pkgs.Tf2Msgs.Action.LookupTransform.Feedback.to_tuple(feedback)}
  end

  def to_struct({goal_id, feedback}) do
    %__MODULE__{
      goal_id: Rclex.Pkgs.UniqueIdentifierMsgs.Msg.UUID.to_struct(goal_id),
      feedback: Rclex.Pkgs.Tf2Msgs.Action.LookupTransform.Feedback.to_struct(feedback)
    }
  end
end
