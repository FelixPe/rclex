defmodule Rclex.TypeDescriptionServer do
  @moduledoc false

  use GenServer, restart: :temporary

  @service_name "GetTypeDescription"

  def start_link(args) do
    name = Keyword.fetch!(args, :name)
    namespace = Keyword.fetch!(args, :namespace)
    GenServer.start_link(__MODULE__, args, name: name(name, namespace))
  end

  def name(name, namespace \\ "/") do
    {:global, {:type_description_server, name, namespace}}
  end

  def service_type, do: Rclex.TypeDescriptionModules.service_module(@service_name)

  def available? do
    Code.ensure_loaded?(service_type()) and
      function_exported?(
        Rclex.Nif,
        :type_description_interfaces_msg_type_description_type_description!,
        0
      )
  end

  def init(args) do
    name = Keyword.fetch!(args, :name)
    namespace = Keyword.fetch!(args, :namespace)
    service_name = "#{namespace}#{name}/get_type_description"

    {:ok, _pid} =
      Rclex.Node.start_service(
        &handle_get_type_description/1,
        service_type(),
        service_name,
        name,
        namespace,
        Rclex.QoS.profile_services_default()
      )

    {:ok, %{name: name, namespace: namespace, service_name: service_name}}
  end

  def terminate(_reason, %{name: name, namespace: namespace, service_name: service_name}) do
    Rclex.Node.stop_service(service_type(), service_name, name, namespace)
  end

  def handle_get_type_description(%{type_name: type_name} = request) do
    case type_name do
      "" -> handle_hash_only_request(request)
      _type_name -> handle_named_request(type_name, request)
    end
  end

  defp handle_hash_only_request(request) do
    type_hash = Map.get(request, :type_hash, "")

    case Rclex.TypeDescriptionRegistry.fetch_by_hash(type_hash) do
      {:ok, description} ->
        build_response(description.type_description.type_name, description, request)

      {:error, :invalid_type_hash} ->
        unavailable_response("invalid type hash")

      {:error, _reason} ->
        unavailable_response("type description not available for #{type_hash}")
    end
  end

  defp handle_named_request(type_name, request) do
    case Rclex.TypeDescriptionRegistry.fetch(type_name) do
      {:ok, description} ->
        case validate_type_hash(type_name, Map.get(request, :type_hash, "")) do
          {:ok, _type_hash} -> build_response(type_name, description, request)
          {:error, reason} -> unavailable_response(reason)
        end

      {:error, :invalid_type_name} ->
        unavailable_response("invalid type name")

      {:error, _reason} ->
        unavailable_response("type description not available for #{type_name}")
    end
  end

  defp build_response(type_name, description, request) do
    response = %{
      successful: true,
      failure_reason: "",
      type_description: description,
      type_sources: type_sources(type_name, request),
      extra_information: []
    }

    Rclex.TypeDescriptionModules.new(response_type(), response)
  end

  defp unavailable_response(reason) do
    Rclex.TypeDescriptionModules.new(response_type(), %{
      successful: false,
      failure_reason: reason
    })
  end

  defp type_sources(_type_name, %{include_type_sources: false}), do: []

  defp type_sources(type_name, _request) do
    case Rclex.TypeDescriptionRegistry.fetch_sources(type_name) do
      {:ok, sources} -> Enum.map(sources, &source_struct/1)
      {:error, _reason} -> []
    end
  end

  defp source_struct(source) do
    Rclex.TypeDescriptionModules.call(
      Rclex.TypeDescriptionModules.message_module("TypeSource"),
      :to_struct,
      [source]
    )
  end

  defp validate_type_hash(_type_name, ""), do: {:ok, :not_requested}

  defp validate_type_hash(type_name, requested_hash) do
    case Rclex.TypeDescriptionRegistry.fetch_hash(type_name) do
      {:ok, ^requested_hash} -> {:ok, requested_hash}
      {:ok, _actual_hash} -> {:error, "type hash does not match #{type_name}"}
      {:error, _reason} -> {:error, "type hash is not available for #{type_name}"}
    end
  end

  defp response_type do
    Rclex.TypeDescriptionModules.call(service_type(), :response_type, [])
  end
end
