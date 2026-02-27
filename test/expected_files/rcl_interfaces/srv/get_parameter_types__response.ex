defmodule Rclex.Pkgs.RclInterfaces.Srv.GetParameterTypes.Response do
  @moduledoc false
  @behaviour Rclex.MessageBehaviour

  defstruct types: <<>>

  @type t :: %__MODULE__{types: binary()}

  alias Rclex.Nif

  def type_support!() do
    apply(Nif, :rcl_interfaces_srv_get_parameter_types__response_type_support!, [])
  end

  def create!() do
    Nif.rcl_interfaces_srv_get_parameter_types__response_create!()
  end

  def destroy!(message) do
    Nif.rcl_interfaces_srv_get_parameter_types__response_destroy!(message)
  end

  def set!(message, %__MODULE__{} = struct) do
    Nif.rcl_interfaces_srv_get_parameter_types__response_set!(message, to_tuple(struct))
  end

  def get!(message) do
    Nif.rcl_interfaces_srv_get_parameter_types__response_get!(message) |> to_struct()
  end

  def to_tuple(%__MODULE__{types: types}) do
    {types}
  end

  def to_struct({types}) do
    %__MODULE__{types: types}
  end
end
