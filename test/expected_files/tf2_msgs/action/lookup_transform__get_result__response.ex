defmodule Rclex.Pkgs.Tf2Msgs.Action.LookupTransform.GetResult.Response do
  @moduledoc false
  @behaviour Rclex.MessageBehaviour

  defstruct status: 0,
            result: %Rclex.Pkgs.Tf2Msgs.Action.LookupTransform.Result{}

  @type t :: %__MODULE__{
          status: byte(),
          result: %Rclex.Pkgs.Tf2Msgs.Action.LookupTransform.Result{}
        }

  alias Rclex.Nif

  def type_support!() do
    apply(Nif, :tf2_msgs_action_lookup_transform__get_result__response_type_support!, [])
  end

  def create!() do
    Nif.tf2_msgs_action_lookup_transform__get_result__response_create!()
  end

  def destroy!(message) do
    Nif.tf2_msgs_action_lookup_transform__get_result__response_destroy!(message)
  end

  def set!(message, %__MODULE__{} = struct) do
    Nif.tf2_msgs_action_lookup_transform__get_result__response_set!(message, to_tuple(struct))
  end

  def get!(message) do
    Nif.tf2_msgs_action_lookup_transform__get_result__response_get!(message) |> to_struct()
  end

  def to_tuple(%__MODULE__{status: status, result: result}) do
    {status, Rclex.Pkgs.Tf2Msgs.Action.LookupTransform.Result.to_tuple(result)}
  end

  def to_struct({status, result}) do
    %__MODULE__{
      status: status,
      result: Rclex.Pkgs.Tf2Msgs.Action.LookupTransform.Result.to_struct(result)
    }
  end
end
