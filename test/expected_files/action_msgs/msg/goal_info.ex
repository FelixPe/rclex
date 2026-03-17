defmodule Rclex.Pkgs.ActionMsgs.Msg.GoalInfo do
  @moduledoc false
  @behaviour Rclex.MessageBehaviour

  defstruct goal_id: %Rclex.Pkgs.UniqueIdentifierMsgs.Msg.UUID{},
            stamp: %Rclex.Pkgs.BuiltinInterfaces.Msg.Time{}

  @type t :: %__MODULE__{
          goal_id: %Rclex.Pkgs.UniqueIdentifierMsgs.Msg.UUID{},
          stamp: %Rclex.Pkgs.BuiltinInterfaces.Msg.Time{}
        }

  alias Rclex.Nif

  def type_support!() do
    apply(Nif, :action_msgs_msg_goal_info_type_support!, [])
  end

  def create!() do
    Nif.action_msgs_msg_goal_info_create!()
  end

  def destroy!(message) do
    Nif.action_msgs_msg_goal_info_destroy!(message)
  end

  def set!(message, %__MODULE__{} = struct) do
    Nif.action_msgs_msg_goal_info_set!(message, to_tuple(struct))
  end

  def get!(message) do
    Nif.action_msgs_msg_goal_info_get!(message) |> to_struct()
  end

  def to_tuple(%__MODULE__{goal_id: goal_id, stamp: stamp}) do
    {Rclex.Pkgs.UniqueIdentifierMsgs.Msg.UUID.to_tuple(goal_id),
     Rclex.Pkgs.BuiltinInterfaces.Msg.Time.to_tuple(stamp)}
  end

  def to_struct({goal_id, stamp}) do
    %__MODULE__{
      goal_id: Rclex.Pkgs.UniqueIdentifierMsgs.Msg.UUID.to_struct(goal_id),
      stamp: Rclex.Pkgs.BuiltinInterfaces.Msg.Time.to_struct(stamp)
    }
  end
end
