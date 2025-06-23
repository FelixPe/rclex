defmodule Rclex.Pkgs.RclInterfaces.Msg.ParameterDescriptor do
  @moduledoc false
  @behaviour Rclex.MessageBehaviour

  defstruct name: "",
            type: 0,
            description: "",
            additional_constraints: "",
            read_only: false,
            dynamic_typing: false,
            floating_point_range: [],
            integer_range: []

  @type t :: %__MODULE__{
          name: String.t(),
          type: byte(),
          description: String.t(),
          additional_constraints: String.t(),
          read_only: boolean(),
          dynamic_typing: boolean(),
          floating_point_range: list(%Rclex.Pkgs.RclInterfaces.Msg.FloatingPointRange{}),
          integer_range: list(%Rclex.Pkgs.RclInterfaces.Msg.IntegerRange{})
        }

  alias Rclex.Nif

  def type_support!() do
    Nif.rcl_interfaces_msg_parameter_descriptor_type_support!()
  end

  def create!() do
    Nif.rcl_interfaces_msg_parameter_descriptor_create!()
  end

  def destroy!(message) do
    Nif.rcl_interfaces_msg_parameter_descriptor_destroy!(message)
  end

  def set!(message, %__MODULE__{} = struct) do
    Nif.rcl_interfaces_msg_parameter_descriptor_set!(message, to_tuple(struct))
  end

  def get!(message) do
    Nif.rcl_interfaces_msg_parameter_descriptor_get!(message) |> to_struct()
  end

  def to_tuple(%__MODULE__{
        name: name,
        type: type,
        description: description,
        additional_constraints: additional_constraints,
        read_only: read_only,
        dynamic_typing: dynamic_typing,
        floating_point_range: floating_point_range,
        integer_range: integer_range
      }) do
    {name, type, description, additional_constraints, read_only, dynamic_typing,
     for struct <- floating_point_range do
       Rclex.Pkgs.RclInterfaces.Msg.FloatingPointRange.to_tuple(struct)
     end,
     for struct <- integer_range do
       Rclex.Pkgs.RclInterfaces.Msg.IntegerRange.to_tuple(struct)
     end}
  end

  def to_struct(
        {name, type, description, additional_constraints, read_only, dynamic_typing,
         floating_point_range, integer_range}
      ) do
    %__MODULE__{
      name: name,
      type: type,
      description: description,
      additional_constraints: additional_constraints,
      read_only: read_only,
      dynamic_typing: dynamic_typing,
      floating_point_range:
        for tuple <- floating_point_range do
          Rclex.Pkgs.RclInterfaces.Msg.FloatingPointRange.to_struct(tuple)
        end,
      integer_range:
        for tuple <- integer_range do
          Rclex.Pkgs.RclInterfaces.Msg.IntegerRange.to_struct(tuple)
        end
    }
  end
end
