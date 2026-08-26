defmodule Rclex.DynamicType do
  @moduledoc """
  Runtime ROS interface type derived from a TypeDescription.

  The module deliberately does not reference the generated
  TypeDescription struct, allowing Rclex to compile before
  type_description_interfaces has been generated.
  """

  alias Rclex.TypeHash
  alias Rclex.Nif

  @enforce_keys [:description, :hash]
  defstruct [:description, :hash]

  @type description :: map()

  @type t :: %__MODULE__{
          description: description(),
          hash: TypeHash.t()
        }

  @spec name(t()) :: String.t()
  def name(%__MODULE__{
        description: %{
          type_description: %{type_name: type_name}
        }
      }) do
    type_name
  end

  @spec from_description(map()) :: {:ok, reference()} | {:error, term()}
  def from_description(description) when is_map(description) do
    Nif.dynamic_type_from_description!(description)
  end

  @spec fill_message(reference(), map()) :: {:ok, reference()} | {:error, term()}
  def fill_message(dynamic_type, message_struct) when is_map(message_struct) do
    Nif.dynamic_type_fill_message!(dynamic_type, message_struct)
  end

  @spec destroy_message(reference()) :: :ok | {:error, term()}
  def destroy_message(dynamic_message) do
    Nif.dynamic_message_destroy!(dynamic_message)
  end

  @spec fini(reference()) :: :ok | {:error, term()}
  def fini(dynamic_type) do
    Nif.dynamic_type_fini!(dynamic_type)
  end
end