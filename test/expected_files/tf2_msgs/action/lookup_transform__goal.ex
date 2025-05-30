defmodule Rclex.Pkgs.Tf2Msgs.Action.LookupTransform.Goal do
  @moduledoc false
  @behaviour Rclex.MessageBehaviour

  defstruct target_frame: "",
            source_frame: "",
            source_time: %Rclex.Pkgs.BuiltinInterfaces.Msg.Time{},
            timeout: %Rclex.Pkgs.BuiltinInterfaces.Msg.Duration{},
            target_time: %Rclex.Pkgs.BuiltinInterfaces.Msg.Time{},
            fixed_frame: "",
            advanced: false

  @type t :: %__MODULE__{
          target_frame: String.t(),
          source_frame: String.t(),
          source_time: %Rclex.Pkgs.BuiltinInterfaces.Msg.Time{},
          timeout: %Rclex.Pkgs.BuiltinInterfaces.Msg.Duration{},
          target_time: %Rclex.Pkgs.BuiltinInterfaces.Msg.Time{},
          fixed_frame: String.t(),
          advanced: boolean()
        }

  alias Rclex.Nif

  def type_support!() do
    Nif.tf2_msgs_action_lookup_transform__goal_type_support!()
  end

  def create!() do
    Nif.tf2_msgs_action_lookup_transform__goal_create!()
  end

  def destroy!(message) do
    Nif.tf2_msgs_action_lookup_transform__goal_destroy!(message)
  end

  def set!(message, %__MODULE__{} = struct) do
    Nif.tf2_msgs_action_lookup_transform__goal_set!(message, to_tuple(struct))
  end

  def get!(message) do
    Nif.tf2_msgs_action_lookup_transform__goal_get!(message) |> to_struct()
  end

  def to_tuple(%__MODULE__{
        target_frame: target_frame,
        source_frame: source_frame,
        source_time: source_time,
        timeout: timeout,
        target_time: target_time,
        fixed_frame: fixed_frame,
        advanced: advanced
      }) do
    {target_frame, source_frame, Rclex.Pkgs.BuiltinInterfaces.Msg.Time.to_tuple(source_time),
     Rclex.Pkgs.BuiltinInterfaces.Msg.Duration.to_tuple(timeout),
     Rclex.Pkgs.BuiltinInterfaces.Msg.Time.to_tuple(target_time), fixed_frame, advanced}
  end

  def to_struct(
        {target_frame, source_frame, source_time, timeout, target_time, fixed_frame, advanced}
      ) do
    %__MODULE__{
      target_frame: target_frame,
      source_frame: source_frame,
      source_time: Rclex.Pkgs.BuiltinInterfaces.Msg.Time.to_struct(source_time),
      timeout: Rclex.Pkgs.BuiltinInterfaces.Msg.Duration.to_struct(timeout),
      target_time: Rclex.Pkgs.BuiltinInterfaces.Msg.Time.to_struct(target_time),
      fixed_frame: fixed_frame,
      advanced: advanced
    }
  end
end
