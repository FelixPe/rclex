defmodule Rclex.TypeDescriptionRegistry do
  @moduledoc false

  alias Rclex.Generators.Util
  alias Rclex.Nif

  def fetch(type_name) when is_binary(type_name) do
    case fetch_with_suffix(type_name, "type_description!") do
      {:ok, description} ->
        {:ok,
         Rclex.TypeDescriptionModules.call(
           Rclex.TypeDescriptionModules.message_module("TypeDescription"),
           :to_struct,
           [description]
         )}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def fetch_sources(type_name) when is_binary(type_name) do
    fetch_with_suffix(type_name, "type_description_sources!")
  end

  def fetch_hash(type_name) when is_binary(type_name) do
    fetch_with_suffix(type_name, "type_hash!")
  end

  defp fetch_with_suffix(type_name, suffix) do
    function = type_name |> Util.type_down_snake() |> then(&String.to_atom("#{&1}_#{suffix}"))

    if function_exported?(Nif, function, 0) do
      {:ok, apply(Nif, function, [])}
    else
      {:error, :not_generated}
    end
  end
end
