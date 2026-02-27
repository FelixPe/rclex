defmodule Rclex.Pkgs.Tf2Msgs.Action.LookupTransform.GetResult.Request do
  @moduledoc false
  @behaviour Rclex.MessageBehaviour

  defstruct goal_id: %Rclex.Pkgs.UniqueIdentifierMsgs.Msg.UUID{}

  @type t :: %__MODULE__{goal_id: %Rclex.Pkgs.UniqueIdentifierMsgs.Msg.UUID{}}

  alias Rclex.Nif

  def type_support!() do
    apply(Nif, :tf2_msgs_action_lookup_transform__get_result__request_type_support!, [])
  end

  def create!() do
    Nif.tf2_msgs_action_lookup_transform__get_result__request_create!()
  end

  def destroy!(message) do
    Nif.tf2_msgs_action_lookup_transform__get_result__request_destroy!(message)
  end

  def set!(message, %__MODULE__{} = struct) do
    Nif.tf2_msgs_action_lookup_transform__get_result__request_set!(message, to_tuple(struct))
  end

  def get!(message) do
    Nif.tf2_msgs_action_lookup_transform__get_result__request_get!(message) |> to_struct()
  end

  def to_tuple(%__MODULE__{goal_id: goal_id}) do
    {Rclex.Pkgs.UniqueIdentifierMsgs.Msg.UUID.to_tuple(goal_id)}
  end

  def to_struct({goal_id}) do
    %__MODULE__{goal_id: Rclex.Pkgs.UniqueIdentifierMsgs.Msg.UUID.to_struct(goal_id)}
  end
end
