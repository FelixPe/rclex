defmodule Rclex.Pkgs.Tf2Msgs.Action.LookupTransform.SendGoal.Response do
  @moduledoc false
  @behaviour Rclex.MessageBehaviour

  defstruct accepted: false,
            stamp: %Rclex.Pkgs.BuiltinInterfaces.Msg.Time{}

  @type t :: %__MODULE__{accepted: boolean(), stamp: %Rclex.Pkgs.BuiltinInterfaces.Msg.Time{}}

  alias Rclex.Nif

  def type_support!() do
    Nif.tf2_msgs_action_lookup_transform__send_goal__response_type_support!()
  end

  def create!() do
    Nif.tf2_msgs_action_lookup_transform__send_goal__response_create!()
  end

  def destroy!(message) do
    Nif.tf2_msgs_action_lookup_transform__send_goal__response_destroy!(message)
  end

  def set!(message, %__MODULE__{} = struct) do
    Nif.tf2_msgs_action_lookup_transform__send_goal__response_set!(message, to_tuple(struct))
  end

  def get!(message) do
    Nif.tf2_msgs_action_lookup_transform__send_goal__response_get!(message) |> to_struct()
  end

  def to_tuple(%__MODULE__{accepted: accepted, stamp: stamp}) do
    {accepted, Rclex.Pkgs.BuiltinInterfaces.Msg.Time.to_tuple(stamp)}
  end

  def to_struct({accepted, stamp}) do
    %__MODULE__{accepted: accepted, stamp: Rclex.Pkgs.BuiltinInterfaces.Msg.Time.to_struct(stamp)}
  end
end
