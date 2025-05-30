defmodule Rclex.Pkgs.Tf2Msgs.Action.LookupTransform.Result do
  @moduledoc false
  @behaviour Rclex.MessageBehaviour

  defstruct transform: %Rclex.Pkgs.GeometryMsgs.Msg.TransformStamped{},
            error: %Rclex.Pkgs.Tf2Msgs.Msg.TF2Error{}

  @type t :: %__MODULE__{
          transform: %Rclex.Pkgs.GeometryMsgs.Msg.TransformStamped{},
          error: %Rclex.Pkgs.Tf2Msgs.Msg.TF2Error{}
        }

  alias Rclex.Nif

  def type_support!() do
    Nif.tf2_msgs_action_lookup_transform__result_type_support!()
  end

  def create!() do
    Nif.tf2_msgs_action_lookup_transform__result_create!()
  end

  def destroy!(message) do
    Nif.tf2_msgs_action_lookup_transform__result_destroy!(message)
  end

  def set!(message, %__MODULE__{} = struct) do
    Nif.tf2_msgs_action_lookup_transform__result_set!(message, to_tuple(struct))
  end

  def get!(message) do
    Nif.tf2_msgs_action_lookup_transform__result_get!(message) |> to_struct()
  end

  def to_tuple(%__MODULE__{transform: transform, error: error}) do
    {Rclex.Pkgs.GeometryMsgs.Msg.TransformStamped.to_tuple(transform),
     Rclex.Pkgs.Tf2Msgs.Msg.TF2Error.to_tuple(error)}
  end

  def to_struct({transform, error}) do
    %__MODULE__{
      transform: Rclex.Pkgs.GeometryMsgs.Msg.TransformStamped.to_struct(transform),
      error: Rclex.Pkgs.Tf2Msgs.Msg.TF2Error.to_struct(error)
    }
  end
end
