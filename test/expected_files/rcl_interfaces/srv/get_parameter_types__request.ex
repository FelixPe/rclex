defmodule Rclex.Pkgs.RclInterfaces.Srv.GetParameterTypes.Request do
  @moduledoc false
  @behaviour Rclex.MessageBehaviour

  defstruct names: []

  @type t :: %__MODULE__{names: list(String.t())}

  alias Rclex.Nif

  def type_support!() do
    apply(Nif, :rcl_interfaces_srv_get_parameter_types__request_type_support!, [])
  end

  def create!() do
    Nif.rcl_interfaces_srv_get_parameter_types__request_create!()
  end

  def destroy!(message) do
    Nif.rcl_interfaces_srv_get_parameter_types__request_destroy!(message)
  end

  def set!(message, %__MODULE__{} = struct) do
    Nif.rcl_interfaces_srv_get_parameter_types__request_set!(message, to_tuple(struct))
  end

  def get!(message) do
    Nif.rcl_interfaces_srv_get_parameter_types__request_get!(message) |> to_struct()
  end

  def to_tuple(%__MODULE__{names: names}) do
    {names}
  end

  def to_struct({names}) do
    %__MODULE__{names: names}
  end
end
