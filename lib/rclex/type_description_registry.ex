defmodule Rclex.TypeDescriptionRegistry do
  @moduledoc false

  alias Rclex.Generators.Util
  alias Rclex.Nif

  def fetch(type_name) when is_binary(type_name) do
    with :ok <- validate_type_name(type_name) do
      type_name
      |> Util.type_down_snake()
      |> fetch_description_by_prefix()
    end
  end

  def fetch_by_hash(type_hash) when is_binary(type_hash) do
    with :ok <- validate_type_hash(type_hash),
         {:ok, prefix} <- provider_prefix_by_hash(type_hash) do
      fetch_description_by_prefix(prefix)
    end
  end

  def fetch_sources(type_name) when is_binary(type_name) do
    fetch_with_suffix(type_name, "type_description_sources!")
  end

  def fetch_hash(type_name) when is_binary(type_name) do
    fetch_with_suffix(type_name, "type_hash!")
  end

  defp fetch_description_by_prefix(prefix) do
    case fetch_with_prefix(prefix, "type_description!") do
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

  defp fetch_with_suffix(type_name, suffix) do
    with :ok <- validate_type_name(type_name) do
      type_name
      |> Util.type_down_snake()
      |> fetch_with_prefix(suffix)
    end
  end

  defp fetch_with_prefix(prefix, suffix) do
    function = String.to_atom("#{prefix}_#{suffix}")

    if function_exported?(Nif, function, 0) do
      {:ok, apply(Nif, function, [])}
    else
      {:error, :not_generated}
    end
  end

  defp provider_prefix_by_hash(type_hash) do
    provider_prefixes()
    |> Enum.find_value({:error, :not_generated}, fn prefix ->
      case fetch_with_prefix(prefix, "type_hash!") do
        {:ok, ^type_hash} -> {:ok, prefix}
        _other -> nil
      end
    end)
  end

  defp provider_prefixes do
    Nif.module_info(:exports)
    |> Enum.flat_map(fn
      {function, 0} ->
        function
        |> Atom.to_string()
        |> String.split("_type_hash!", parts: 2)
        |> case do
          [prefix, ""] -> [prefix]
          _other -> []
        end

      _export ->
        []
    end)
  end

  defp validate_type_name(type_name) do
    case String.split(type_name, "/") do
      [package, kind, name]
      when package != "" and kind in ["msg", "srv", "action"] and name != "" ->
        :ok

      _invalid ->
        {:error, :invalid_type_name}
    end
  end

  defp validate_type_hash(""), do: {:error, :invalid_type_hash}
  defp validate_type_hash("RIHS" <> _hash), do: :ok
  defp validate_type_hash(_type_hash), do: {:error, :invalid_type_hash}
end
