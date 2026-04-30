defmodule Rclex.ParameterClient do
  @moduledoc """
  Provides a client to access parameters on remote ROS 2 nodes via the
  standard parameter services.

  Inspired by `rclpy.parameter_client.AsyncParameterClient`. A client must be
  started on a local node before it can communicate with the parameter
  services of a remote (server) node.

  This module follows the rule of "one process per service client": when a
  parameter client is started, six service clients are registered on the
  given local (client) node, one for each parameter service:

  - `~/get_parameters`
  - `~/set_parameters`
  - `~/set_parameters_atomically`
  - `~/list_parameters`
  - `~/describe_parameters`
  - `~/get_parameter_types`
  """

  require Logger

  alias Rclex.Client
  alias Rclex.QoS
  alias Rclex.ParameterHelpers

  alias Rclex.Pkgs.RclInterfaces.Srv.{
    GetParameters,
    SetParameters,
    SetParametersAtomically,
    ListParameters,
    DescribeParameters,
    GetParameterTypes
  }

  @services [
    {GetParameters, "get_parameters"},
    {SetParameters, "set_parameters"},
    {SetParametersAtomically, "set_parameters_atomically"},
    {ListParameters, "list_parameters"},
    {DescribeParameters, "describe_parameters"},
    {GetParameterTypes, "get_parameter_types"}
  ]

  @doc """
  Start the six parameter service clients on the given local node, all
  pointing at the parameter services of the remote `server_node_name` (in
  `server_namespace`).

  ## Options

  - `:namespace` — namespace of the *local* (client) node. Defaults to `"/"`.
  - `:server_namespace` — namespace of the *remote* (server) node. Defaults
    to `"/"`.
  - `:qos` — service QoS. Defaults to `Rclex.QoS.profile_services_default/0`.
  """
  @spec start(
          server_node_name :: String.t(),
          client_node_name :: String.t(),
          opts :: keyword()
        ) :: :ok | {:error, term()}
  def start(server_node_name, client_node_name, opts \\ [])
      when is_binary(server_node_name) and is_binary(client_node_name) and is_list(opts) do
    namespace = Keyword.get(opts, :namespace, "/")
    server_namespace = Keyword.get(opts, :server_namespace, "/")
    qos = Keyword.get(opts, :qos, QoS.profile_services_default())

    # No-op callback; we only ever use call_timeout/4 against these clients.
    callback = fn _request, _response -> :ok end

    Enum.reduce_while(@services, :ok, fn {service_type, service_suffix}, _acc ->
      service_name = service_name(server_namespace, server_node_name, service_suffix)

      case Rclex.start_client(callback, service_type, service_name, client_node_name,
             namespace: namespace,
             qos: qos
           ) do
        :ok ->
          {:cont, :ok}

        {:error, :already_started} ->
          {:cont, :ok}

        {:error, reason} ->
          # Best effort cleanup on failure
          _ = stop(server_node_name, client_node_name, opts)
          {:halt, {:error, reason}}
      end
    end)
  end

  @doc """
  Stop all parameter service clients previously started by `start/3` for the
  given `server_node_name`/`client_node_name` pair.

  Same options as `start/3`.
  """
  @spec stop(
          server_node_name :: String.t(),
          client_node_name :: String.t(),
          opts :: keyword()
        ) :: :ok
  def stop(server_node_name, client_node_name, opts \\ [])
      when is_binary(server_node_name) and is_binary(client_node_name) and is_list(opts) do
    namespace = Keyword.get(opts, :namespace, "/")
    server_namespace = Keyword.get(opts, :server_namespace, "/")

    Enum.each(@services, fn {service_type, service_suffix} ->
      service_name = service_name(server_namespace, server_node_name, service_suffix)
      _ = Rclex.stop_client(service_type, service_name, client_node_name, namespace: namespace)
    end)

    :ok
  end

  @doc """
  Returns `true` if the remote parameter services are available, `false`
  otherwise. Returns `{:error, :not_found}` if the parameter client has not
  been started.

  By default, the check is performed against `get_parameters`. All six
  services are typically registered together by the server, so this is
  representative.
  """
  @spec service_available?(
          server_node_name :: String.t(),
          client_node_name :: String.t(),
          opts :: keyword()
        ) :: boolean() | {:error, :not_found}
  def service_available?(server_node_name, client_node_name, opts \\ [])
      when is_binary(server_node_name) and is_binary(client_node_name) and is_list(opts) do
    namespace = Keyword.get(opts, :namespace, "/")
    server_namespace = Keyword.get(opts, :server_namespace, "/")
    service_name = service_name(server_namespace, server_node_name, "get_parameters")

    Client.service_server_available?(GetParameters, service_name, client_node_name, namespace)
  end

  # ---- Get -----------------------------------------------------------------

  @doc """
  Get the values of `parameter_names` from the remote node.

  Returns `{:ok, [{name, value}, ...]}` on success, where `value` is the
  Elixir-side decoded value (or `nil` if the parameter is not set on the
  server). Returns `{:error, reason}` on failure.

  ## Options

  - `:namespace` (client node namespace, default `"/"`)
  - `:server_namespace` (default `"/"`)
  - `:timeout` (seconds, float; default `nil` for infinite)
  """
  @spec get_parameters(
          server_node_name :: String.t(),
          parameter_names :: [String.t()],
          client_node_name :: String.t(),
          opts :: keyword()
        ) :: {:ok, [{String.t(), term()}]} | {:error, term()}
  def get_parameters(server_node_name, parameter_names, client_node_name, opts \\ [])
      when is_binary(server_node_name) and is_list(parameter_names) and
             is_binary(client_node_name) and is_list(opts) do
    request = %GetParameters.Request{names: parameter_names}

    with {:ok, %GetParameters.Response{values: values}} <-
           call(
             GetParameters,
             "get_parameters",
             request,
             server_node_name,
             client_node_name,
             opts
           ) do
      decoded =
        parameter_names
        |> Enum.zip(values)
        |> Enum.map(fn {name, value} ->
          {name, ParameterHelpers.parameter_value_to_elixir(value)}
        end)

      {:ok, decoded}
    end
  end

  @doc """
  Get the parameter types of `parameter_names` on the remote node.

  Returns `{:ok, [integer]}` on success, where each integer matches the
  ROS 2 `ParameterType` constants (e.g. `parameter_integer`).
  """
  @spec get_parameter_types(
          server_node_name :: String.t(),
          parameter_names :: [String.t()],
          client_node_name :: String.t(),
          opts :: keyword()
        ) :: {:ok, [non_neg_integer()]} | {:error, term()}
  def get_parameter_types(server_node_name, parameter_names, client_node_name, opts \\ [])
      when is_binary(server_node_name) and is_list(parameter_names) and
             is_binary(client_node_name) and is_list(opts) do
    request = %GetParameterTypes.Request{names: parameter_names}

    with {:ok, %GetParameterTypes.Response{types: types}} <-
           call(
             GetParameterTypes,
             "get_parameter_types",
             request,
             server_node_name,
             client_node_name,
             opts
           ) do
      {:ok, types}
    end
  end

  @doc """
  Describe `parameter_names` on the remote node. If `parameter_names` is
  empty, all parameters are described.

  Returns `{:ok, [%ParameterDescriptor{}]}` on success.
  """
  @spec describe_parameters(
          server_node_name :: String.t(),
          parameter_names :: [String.t()],
          client_node_name :: String.t(),
          opts :: keyword()
        ) :: {:ok, [struct()]} | {:error, term()}
  def describe_parameters(server_node_name, parameter_names, client_node_name, opts \\ [])
      when is_binary(server_node_name) and is_list(parameter_names) and
             is_binary(client_node_name) and is_list(opts) do
    request = %DescribeParameters.Request{names: parameter_names}

    with {:ok, %DescribeParameters.Response{descriptors: descriptors}} <-
           call(
             DescribeParameters,
             "describe_parameters",
             request,
             server_node_name,
             client_node_name,
             opts
           ) do
      {:ok, descriptors}
    end
  end

  @doc """
  List parameters on the remote node.

  ## Options

  - `:prefixes` — list of prefix strings to filter by. Defaults to `[]`
    (no filtering).
  - `:depth` — recursion depth. Defaults to `0` (unlimited).
  - `:namespace`, `:server_namespace`, `:timeout` — as elsewhere.

  Returns `{:ok, %{names: [...], prefixes: [...]}}` on success.
  """
  @spec list_parameters(
          server_node_name :: String.t(),
          client_node_name :: String.t(),
          opts :: keyword()
        ) :: {:ok, %{names: [String.t()], prefixes: [String.t()]}} | {:error, term()}
  def list_parameters(server_node_name, client_node_name, opts \\ [])
      when is_binary(server_node_name) and is_binary(client_node_name) and is_list(opts) do
    prefixes = Keyword.get(opts, :prefixes, [])
    depth = Keyword.get(opts, :depth, 0)

    request = %ListParameters.Request{prefixes: prefixes, depth: depth}

    with {:ok, %ListParameters.Response{result: result}} <-
           call(
             ListParameters,
             "list_parameters",
             request,
             server_node_name,
             client_node_name,
             opts
           ) do
      {:ok, %{names: result.names, prefixes: result.prefixes}}
    end
  end

  # ---- Set -----------------------------------------------------------------

  @doc """
  Set parameters on the remote node, one by one.

  `parameters` is a list of `{name, value}` tuples or `%Rclex.Pkgs.RclInterfaces.Msg.Parameter{}`
  structs. Each set is independently validated server-side.

  Returns `{:ok, [%SetParametersResult{}]}` on success.
  """
  @spec set_parameters(
          server_node_name :: String.t(),
          parameters :: [{String.t(), term()} | struct()],
          client_node_name :: String.t(),
          opts :: keyword()
        ) :: {:ok, [struct()]} | {:error, term()}
  def set_parameters(server_node_name, parameters, client_node_name, opts \\ [])
      when is_binary(server_node_name) and is_list(parameters) and
             is_binary(client_node_name) and is_list(opts) do
    request = %SetParameters.Request{parameters: build_parameter_structs(parameters)}

    with {:ok, %SetParameters.Response{results: results}} <-
           call(
             SetParameters,
             "set_parameters",
             request,
             server_node_name,
             client_node_name,
             opts
           ) do
      {:ok, results}
    end
  end

  @doc """
  Set parameters on the remote node atomically: either all set successfully
  or none change.

  Returns `{:ok, %SetParametersResult{}}` on success.
  """
  @spec set_parameters_atomically(
          server_node_name :: String.t(),
          parameters :: [{String.t(), term()} | struct()],
          client_node_name :: String.t(),
          opts :: keyword()
        ) :: {:ok, struct()} | {:error, term()}
  def set_parameters_atomically(server_node_name, parameters, client_node_name, opts \\ [])
      when is_binary(server_node_name) and is_list(parameters) and
             is_binary(client_node_name) and is_list(opts) do
    request = %SetParametersAtomically.Request{parameters: build_parameter_structs(parameters)}

    with {:ok, %SetParametersAtomically.Response{result: result}} <-
           call(
             SetParametersAtomically,
             "set_parameters_atomically",
             request,
             server_node_name,
             client_node_name,
             opts
           ) do
      {:ok, result}
    end
  end

  # ---- Internals -----------------------------------------------------------

  defp call(_service_type, suffix, request, server_node_name, client_node_name, opts) do
    namespace = Keyword.get(opts, :namespace, "/")
    server_namespace = Keyword.get(opts, :server_namespace, "/")
    timeout_sec = Keyword.get(opts, :timeout)

    service_name = service_name(server_namespace, server_node_name, suffix)

    Client.call_timeout(
      request,
      service_name,
      client_node_name,
      namespace,
      timeout_sec
    )
  end

  @doc false
  # Build the fully-qualified service name used by the remote parameter
  # server. Matches `Rclex.ParameterServer.start_services/2`'s formula:
  # `"<server_namespace><server_node_name>/<suffix>"`.
  def service_name(server_namespace, server_node_name, suffix) do
    "#{server_namespace}#{server_node_name}/#{suffix}"
  end

  defp build_parameter_structs(parameters) do
    Enum.map(parameters, fn
      %Rclex.Pkgs.RclInterfaces.Msg.Parameter{} = p ->
        p

      {name, %Rclex.Pkgs.RclInterfaces.Msg.ParameterValue{} = value} ->
        ParameterHelpers.gen_parameter_struct(name, value)

      {name, value} ->
        ParameterHelpers.gen_parameter_struct(
          name,
          ParameterHelpers.gen_parameter_value_struct(value)
        )

      {name, value, type} ->
        ParameterHelpers.gen_parameter_struct(
          name,
          ParameterHelpers.gen_parameter_value_struct(value, type)
        )
    end)
  end
end
