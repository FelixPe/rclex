defmodule Rclex.Pkgs.RclInterfaces.Msg.ParameterDescriptor do
  @moduledoc false
  @behaviour Rclex.MessageBehaviour

  defstruct name: "",
            type: 0,
            description: "",
            additional_constraints: ""

  @type t :: %__MODULE__{
          name: String.t(),
          type: byte(),
          description: String.t(),
          additional_constraints: String.t()
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
        additional_constraints: additional_constraints
      }) do
    {~c"#{name}", type, ~c"#{description}", ~c"#{additional_constraints}"}
  end

  def to_struct({name, type, description, additional_constraints}) do
    %__MODULE__{
      name: "#{name}",
      type: type,
      description: "#{description}",
      additional_constraints: "#{additional_constraints}"
    }
  end
end
