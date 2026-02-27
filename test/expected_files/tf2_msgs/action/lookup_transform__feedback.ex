defmodule Rclex.Pkgs.Tf2Msgs.Action.LookupTransform.Feedback do
  @moduledoc false
  @behaviour Rclex.MessageBehaviour

  defstruct []

  @type t :: %__MODULE__{}

  alias Rclex.Nif

  def type_support!() do
    apply(Nif, :tf2_msgs_action_lookup_transform__feedback_type_support!, [])
  end

  def create!() do
    Nif.tf2_msgs_action_lookup_transform__feedback_create!()
  end

  def destroy!(message) do
    Nif.tf2_msgs_action_lookup_transform__feedback_destroy!(message)
  end

  def set!(message, %__MODULE__{} = struct) do
    Nif.tf2_msgs_action_lookup_transform__feedback_set!(message, to_tuple(struct))
  end

  def get!(message) do
    Nif.tf2_msgs_action_lookup_transform__feedback_get!(message) |> to_struct()
  end

  def to_tuple(%__MODULE__{}) do
    {}
  end

  def to_struct({}) do
    %__MODULE__{}
  end
end
