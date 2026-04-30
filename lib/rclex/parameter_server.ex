defmodule Rclex.ParameterServer do
  @moduledoc """
  Provides parameter service functionality for ROS 2 nodes.

  This module implements the standard ROS 2 parameter services:
  - ~/get_parameters
  - ~/set_parameters
  - ~/set_parameters_atomically
  - ~/list_parameters
  - ~/describe_parameters
  - ~/get_parameter_types
  """

  use GenServer, restart: :temporary
  require Logger

  @parameter_events_topic "/parameter_events"
  @parameter_event_descriptors_topic "/parameter_event_descriptors"

  import Rclex.ParameterHelpers
  import Rclex.ActionHelpers, only: [gen_time_struct: 1]

  def start_link(args) do
    name = Keyword.fetch!(args, :name)
    namespace = Keyword.fetch!(args, :namespace)

    GenServer.start_link(__MODULE__, args, name: name(name, namespace))
  end

  def name(name, namespace \\ "/") do
    {:global, {:parameter_server, name, namespace}}
  end

  # Parameter management functions
  @doc """
  Declare a parameter on the node.

  Parameters must be declared before they can be set or retrieved.
  """
  def declare_parameter(
        name,
        namespace,
        parameter_name,
        opts \\ []
      ) do
    server = name(name, namespace)

    GenServer.call(
      server,
      {:declare_parameter, parameter_name, opts}
    )
  end

  @doc """
  Get the value of a parameter.

  Returns {:ok, value} if the parameter exists, {:error, reason} otherwise.
  """
  def get_parameter(name, namespace, parameter_name) do
    server = name(name, namespace)
    GenServer.call(server, {:get_parameter, parameter_name})
  end

  @doc """
  Set single parameter.

  Returns :ok if the parameter was set successfully, {:error, reason} otherwise.
  """
  def set_parameter(name, namespace, parameter_name, value, opts \\ []) do
    server = name(name, namespace)
    parameter_type = Keyword.get(opts, :type, :undefined)
    parameter_value = Rclex.ParameterHelpers.gen_parameter_value_struct(value, parameter_type)
    GenServer.call(server, {:set_parameter, parameter_name, parameter_value})
  end

  @doc """
  Set multiple parameters atomically.

  Returns :ok if all parameters were set successfully, {:error, reason} otherwise.
  """
  def set_parameters(name, namespace, parameters, convert \\ false, atomically \\ true) do
    server = name(name, namespace)

    GenServer.call(server, {:set_parameters, parameters, atomically, convert})
  end

  @doc """
  List all declared parameters.

  Get a list of parameter names and their prefixes.

  Returns a list of parameter names.
  """
  def list_parameters(name, namespace) do
    server = name(name, namespace)
    GenServer.call(server, {:list_parameters})
  end

  @doc """
  Get parameter descriptors for the given parameter names.

  If no names are provided, returns descriptors for all parameters.
  """
  def describe_parameters(name, namespace, parameter_names \\ []) do
    server = name(name, namespace)
    GenServer.call(server, {:describe_parameters, parameter_names})
  end

  @doc """
  Get parameter types for the given parameter names.

  Returns a list of parameter types corresponding to the parameter names.
  """
  def get_parameter_types(name, namespace, parameter_names) do
    server = name(name, namespace)
    GenServer.call(server, {:get_parameter_types, parameter_names})
  end

  @doc """
  Add a pre-set callback for parameter updates.

  The callback receives a list of `{name, parameter_value}` tuples and may
  return a modified list.
  """
  def add_pre_set_parameters_callback(name, namespace, callback) do
    server = name(name, namespace)
    GenServer.call(server, {:add_pre_set_parameters_callback, callback})
  end

  @doc """
  Remove a pre-set callback.
  """
  def remove_pre_set_parameters_callback(name, namespace, callback) do
    server = name(name, namespace)
    GenServer.call(server, {:remove_pre_set_parameters_callback, callback})
  end

  @doc """
  Add an on-set callback for parameter updates.

  The callback receives a list of `{name, parameter_value}` tuples and may
  approve or reject the update.
  """
  def add_on_set_parameters_callback(name, namespace, callback) do
    server = name(name, namespace)
    GenServer.call(server, {:add_on_set_parameters_callback, callback})
  end

  @doc """
  Remove an on-set callback.
  """
  def remove_on_set_parameters_callback(name, namespace, callback) do
    server = name(name, namespace)
    GenServer.call(server, {:remove_on_set_parameters_callback, callback})
  end

  @doc """
  Add a post-set callback for parameter updates.

  The callback is invoked with `(parameter_name, new_value, old_value)`.
  """
  def add_post_set_parameters_callback(name, namespace, callback) do
    server = name(name, namespace)
    GenServer.call(server, {:add_post_set_parameters_callback, callback})
  end

  @doc """
  Remove a post-set callback.
  """
  def remove_post_set_parameters_callback(name, namespace, callback) do
    server = name(name, namespace)
    GenServer.call(server, {:remove_post_set_parameters_callback, callback})
  end

  defp start_services(node_name, node_namespace) do
    # Get Parameters service
    {:ok, _pid} =
      Rclex.Node.start_service(
        &handle_get_parameters(&1, node_name, node_namespace),
        Rclex.Pkgs.RclInterfaces.Srv.GetParameters,
        "#{node_namespace}#{node_name}/get_parameters",
        node_name,
        node_namespace,
        Rclex.QoS.profile_services_default()
      )

    # Set Parameters service
    {:ok, _pid} =
      Rclex.Node.start_service(
        &handle_set_parameters(&1, node_name, node_namespace),
        Rclex.Pkgs.RclInterfaces.Srv.SetParameters,
        "#{node_namespace}#{node_name}/set_parameters",
        node_name,
        node_namespace,
        Rclex.QoS.profile_services_default()
      )

    # Set Parameters Atomically service
    {:ok, _pid} =
      Rclex.Node.start_service(
        &handle_set_parameters_atomically(&1, node_name, node_namespace),
        Rclex.Pkgs.RclInterfaces.Srv.SetParametersAtomically,
        "#{node_namespace}#{node_name}/set_parameters_atomically",
        node_name,
        node_namespace,
        Rclex.QoS.profile_services_default()
      )

    # List Parameters service
    {:ok, _pid} =
      Rclex.Node.start_service(
        &handle_list_parameters(&1, node_name, node_namespace),
        Rclex.Pkgs.RclInterfaces.Srv.ListParameters,
        "#{node_namespace}#{node_name}/list_parameters",
        node_name,
        node_namespace,
        Rclex.QoS.profile_services_default()
      )

    # Describe Parameters service
    {:ok, _pid} =
      Rclex.Node.start_service(
        &handle_describe_parameters(&1, node_name, node_namespace),
        Rclex.Pkgs.RclInterfaces.Srv.DescribeParameters,
        "#{node_namespace}#{node_name}/describe_parameters",
        node_name,
        node_namespace,
        Rclex.QoS.profile_services_default()
      )

    # Get Parameter Types service
    {:ok, _pid} =
      Rclex.Node.start_service(
        &handle_get_parameter_types(&1, node_name, node_namespace),
        Rclex.Pkgs.RclInterfaces.Srv.GetParameterTypes,
        "#{node_namespace}#{node_name}/get_parameter_types",
        node_name,
        node_namespace,
        Rclex.QoS.profile_services_default()
      )
  end

  defp start_parameter_event_publisher(node_name, node_namespace) do
    case Rclex.Node.start_publisher(
           Rclex.Pkgs.RclInterfaces.Msg.ParameterEvent,
           @parameter_events_topic,
           node_name,
           node_namespace,
           Rclex.QoS.profile_parameter_events()
         ) do
      {:ok, publisher} ->
        {:ok, publisher}

      error ->
        Logger.error("Failed to start parameter event publisher: #{inspect(error)}")
        {:error, error}
    end
  end

  defp start_parameter_event_descriptors_publisher(node_name, node_namespace) do
    case Rclex.Node.start_publisher(
           Rclex.Pkgs.RclInterfaces.Msg.ParameterEventDescriptors,
           @parameter_event_descriptors_topic,
           node_name,
           node_namespace,
           Rclex.QoS.profile_parameter_events()
         ) do
      {:ok, publisher} ->
        {:ok, publisher}

      error ->
        Logger.error("Failed to start parameter event descriptors publisher: #{inspect(error)}")
        {:error, error}
    end
  end

  defp stop_parameter_event_publisher(node_name, node_namespace) do
    case Rclex.Node.stop_publisher(
           Rclex.Pkgs.RclInterfaces.Msg.ParameterEvent,
           @parameter_events_topic,
           node_name,
           node_namespace
         ) do
      :ok ->
        :ok

      error ->
        Logger.error("Failed to stop parameter event publisher: #{inspect(error)}")
        {:error, error}
    end
  end

  defp stop_parameter_event_descriptors_publisher(node_name, node_namespace) do
    case Rclex.Node.stop_publisher(
           Rclex.Pkgs.RclInterfaces.Msg.ParameterEventDescriptors,
           @parameter_event_descriptors_topic,
           node_name,
           node_namespace
         ) do
      :ok ->
        :ok

      error ->
        Logger.error("Failed to stop parameter event descriptors publisher: #{inspect(error)}")
        {:error, error}
    end
  end

  defp stop_services(node_name, node_namespace) do
    services = [
      {Rclex.Pkgs.RclInterfaces.Srv.GetParameters,
       "#{node_namespace}#{node_name}/get_parameters"},
      {Rclex.Pkgs.RclInterfaces.Srv.SetParameters,
       "#{node_namespace}#{node_name}/set_parameters"},
      {Rclex.Pkgs.RclInterfaces.Srv.SetParametersAtomically,
       "#{node_namespace}#{node_name}/set_parameters_atomically"},
      {Rclex.Pkgs.RclInterfaces.Srv.ListParameters,
       "#{node_namespace}#{node_name}/list_parameters"},
      {Rclex.Pkgs.RclInterfaces.Srv.DescribeParameters,
       "#{node_namespace}#{node_name}/describe_parameters"},
      {Rclex.Pkgs.RclInterfaces.Srv.GetParameterTypes,
       "#{node_namespace}#{node_name}/get_parameter_types"}
    ]

    Enum.each(services, fn {service_type, service_name} ->
      case Rclex.Node.stop_service(service_type, service_name, node_name, node_namespace) do
        :ok ->
          :ok

        {:error, :not_found} ->
          Logger.warning("Failed to stop service #{service_name}, already terminated?")
      end
    end)
  end

  def init(args) do
    Process.flag(:trap_exit, true)

    name = Keyword.fetch!(args, :name)
    namespace = Keyword.fetch!(args, :namespace)

    {:ok, parameter_event_publisher} = start_parameter_event_publisher(name, namespace)

    {:ok, parameter_event_descriptors_publisher} =
      start_parameter_event_descriptors_publisher(name, namespace)

    start_services(name, namespace)

    # Initialize the parameter server's state
    {:ok,
     %{
       name: name,
       namespace: namespace,
       parameters: %{},
       parameter_descriptors: %{},
       pre_set_parameters_callbacks: [],
       on_set_parameters_callbacks: [],
       post_set_parameters_callbacks: [],
       parameter_event_publisher: parameter_event_publisher,
       parameter_event_descriptors_publisher: parameter_event_descriptors_publisher
     }}
  end

  def terminate(
        _reason,
        %{
          name: name,
          namespace: namespace
        } = state
      ) do
    # Stop all parameter services
    stop_services(name, namespace)

    if state.parameter_event_publisher do
      stop_parameter_event_publisher(name, namespace)
    end

    if state.parameter_event_descriptors_publisher do
      stop_parameter_event_descriptors_publisher(name, namespace)
    end

    :ok
  end

  # Service handlers

  def handle_get_parameters(%{names: names}, node_name, node_namespace) do
    values =
      Enum.map(names, fn name ->
        case Rclex.ParameterServer.get_parameter(node_name, node_namespace, name) do
          {:ok, value} -> value
          {:error, _} -> gen_parameter_value_struct(nil, :not_set)
        end
      end)

    gen_get_parameters_response_struct(values)
  end

  def handle_set_parameters(%{parameters: parameters}, node_name, node_namespace) do
    # Convert parameters to name-value pairs
    param_pairs =
      Enum.map(parameters, fn %{name: name, value: param_value} ->
        {name, param_value}
      end)

    results =
      Rclex.ParameterServer.set_parameters(node_name, node_namespace, param_pairs, false, false)

    gen_set_parameters_response_struct(results)
  end

  def handle_set_parameters_atomically(%{parameters: parameters}, node_name, node_namespace) do
    # Convert parameters to name-value pairs
    param_pairs =
      Enum.map(parameters, fn %{name: name, value: param_value} ->
        {name, param_value}
      end)

    case Rclex.ParameterServer.set_parameters(node_name, node_namespace, param_pairs, false, true) do
      :ok ->
        gen_set_parameters_atomically_response_struct(true, "")

      {:error, reason} ->
        gen_set_parameters_atomically_response_struct(false, to_string(reason))
    end
  end

  defp matches_prefix?(param_name, prefix) do
    param_name == prefix or String.starts_with?(param_name, "#{prefix}.")
  end

  defp starts_with_any_prefix?(param_name, prefixes) do
    Enum.any?(prefixes, fn prefix -> matches_prefix?(param_name, prefix) end)
  end

  defp filter_parameters_by_prefixes(all_params, []) do
    {all_params, []}
  end

  defp filter_parameters_by_prefixes(all_params, prefixes) do
    filtered_params = Enum.filter(all_params, &starts_with_any_prefix?(&1, prefixes))

    matched_prefixes =
      Enum.filter(prefixes, fn prefix ->
        Enum.any?(filtered_params, &matches_prefix?(&1, prefix))
      end)

    {filtered_params, matched_prefixes}
  end

  def handle_list_parameters(%{prefixes: prefixes, depth: depth}, node_name, node_namespace) do
    all_params = Rclex.ParameterServer.list_parameters(node_name, node_namespace)

    # Filter by prefixes if provided
    {filtered_params, filtered_prefixes} = filter_parameters_by_prefixes(all_params, prefixes)

    # Apply depth filtering if specified
    final_params =
      if depth > 0 do
        Enum.filter(filtered_params, fn param_name ->
          parts = String.split(param_name, ".")
          length(parts) <= depth
        end)
      else
        filtered_params
      end

    # Generate response with unique prefixes
    gen_list_parameters_response_struct(final_params, filtered_prefixes)
  end

  def handle_describe_parameters(%{names: names}, node_name, node_namespace) do
    descriptors = Rclex.ParameterServer.describe_parameters(node_name, node_namespace, names)

    gen_describe_parameters_response_struct(descriptors)
  end

  def handle_get_parameter_types(%{names: names}, node_name, node_namespace) do
    types = Rclex.ParameterServer.get_parameter_types(node_name, node_namespace, names)

    # Convert parameter types to integers
    type_ints =
      Enum.map(types, fn type ->
        parameter_type_to_ros2(type)
      end)

    gen_get_parameter_types_response_struct(:erlang.list_to_binary(type_ints))
  end

  # Parameter management callbacks

  def handle_call(
        {:declare_parameter, parameter_name, _opts},
        _from,
        state
      )
      when parameter_name == "" do
    {:reply, {:error, "parameter name must not be empty"}, state}
  end

  def handle_call(
        {:declare_parameter, parameter_name, opts},
        _from,
        state
      ) do
    alias Rclex.Parameter

    # Extract options
    parameter_type = Keyword.get(opts, :type, :undefined)
    default_value = Keyword.get(opts, :default_value, nil)

    # Check if parameter is already declared
    if Map.has_key?(state.parameters, parameter_name) do
      {:reply, {:error, :already_declared}, state}
    else
      # Set default value if provided
      param_value =
        if default_value != nil do
          gen_parameter_value_struct(default_value, parameter_type)
        else
          gen_parameter_value_struct(nil, :not_set)
        end

      # Create descriptor if not provided
      param_descriptor =
        Parameter.descriptor(parameter_name, Parameter.parameter_value_type(param_value), opts)

      new_parameters = Map.put(state.parameters, parameter_name, param_value)
      new_descriptors = Map.put(state.parameter_descriptors, parameter_name, param_descriptor)

      new_state = %{state | parameters: new_parameters, parameter_descriptors: new_descriptors}

      # Notify callbacks about new parameter
      notify_parameter_callbacks(
        state.post_set_parameters_callbacks,
        parameter_name,
        param_value,
        nil
      )

      if state.parameter_event_publisher do
        publish_parameter_event(
          state.name,
          state.namespace,
          %{parameter_name => param_value},
          %{},
          %{}
        )
      end

      {:reply, :ok, new_state}
    end
  end

  def handle_call({:get_parameter, parameter_name}, _from, state) do
    case Map.get(state.parameters, parameter_name) do
      nil ->
        {:reply, {:error, :not_declared}, state}

      param_value ->
        {:reply, {:ok, param_value}, state}
    end
  end

  def handle_call({:set_parameter, parameter_name, parameter_value}, _from, state) do
    parameters =
      apply_pre_set_parameter_callbacks(state.pre_set_parameters_callbacks, [
        {parameter_name, parameter_value}
      ])

    case run_on_set_parameter_callbacks(state.on_set_parameters_callbacks, parameters) do
      :ok ->
        case parameters do
          [{resolved_name, resolved_value}] ->
            do_handle_set_parameter_resolved(resolved_name, resolved_value, state)

          _ ->
            {:reply, {:error, :invalid_pre_set_callback_output}, state}
        end

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:set_parameters, parameters, false}, from, state) do
    handle_call({:set_parameters, parameters, false, false}, from, state)
  end

  def handle_call({:set_parameters, parameters, true}, from, state) do
    handle_call({:set_parameters, parameters, true, false}, from, state)
  end

  def handle_call({:set_parameters, parameters, false, convert}, _from, state) do
    converted_parameters = convert_parameters_for_set(parameters, convert, state)

    processed_parameters =
      apply_pre_set_parameter_callbacks(state.pre_set_parameters_callbacks, converted_parameters)

    case run_on_set_parameter_callbacks(state.on_set_parameters_callbacks, processed_parameters) do
      {:error, reason} ->
        results =
          Enum.map(processed_parameters, fn _ ->
            gen_set_parameters_result_struct(false, to_string(reason))
          end)

        {:reply, results, state}

      :ok ->
        {results, changed_parameters, new_descriptors, changed_descriptors, new_state} =
          Enum.reduce(processed_parameters, {[], %{}, [], [], state}, fn {parameter_name,
                                                                          param_value},
                                                                         {results,
                                                                          changed_parameters,
                                                                          new_descriptors,
                                                                          changed_descriptors,
                                                                          state} ->
            set_one_parameter(
              parameter_name,
              param_value,
              results,
              changed_parameters,
              new_descriptors,
              changed_descriptors,
              state
            )
          end)

        if state.parameter_event_publisher do
          publish_parameter_event(
            state.name,
            state.namespace,
            %{},
            changed_parameters,
            %{}
          )
        end

        if state.parameter_event_descriptors_publisher do
          publish_parameter_event_descriptors(
            state.name,
            state.namespace,
            new_descriptors,
            changed_descriptors,
            []
          )
        end

        {:reply, results, new_state}
    end
  end

  def handle_call({:set_parameters, parameters, true, convert}, _from, state) do
    converted_parameters = convert_parameters_for_set(parameters, convert, state)

    processed_parameters =
      apply_pre_set_parameter_callbacks(state.pre_set_parameters_callbacks, converted_parameters)

    case run_on_set_parameter_callbacks(state.on_set_parameters_callbacks, processed_parameters) do
      {:error, reason} ->
        {:reply, {:error, reason}, state}

      :ok ->
        process_set_parameters_with_convert(processed_parameters, state)
    end
  end

  def handle_call({:list_parameters}, _from, state) do
    parameter_names = Map.keys(state.parameters)
    {:reply, parameter_names, state}
  end

  def handle_call({:describe_parameters, parameter_names}, _from, state) do
    names_to_describe =
      if Enum.empty?(parameter_names) do
        Map.keys(state.parameter_descriptors)
      else
        parameter_names
      end

    descriptors =
      Enum.map(names_to_describe, fn name ->
        Map.get(state.parameter_descriptors, name)
      end)
      |> Enum.filter(&(&1 != nil))

    {:reply, descriptors, state}
  end

  def handle_call({:get_parameter_types, parameter_names}, _from, state) do
    types =
      Enum.map(parameter_names, fn name ->
        case Map.get(state.parameters, name) do
          nil -> :not_declared
          param_value -> Rclex.Parameter.parameter_value_type(param_value)
        end
      end)

    {:reply, types, state}
  end

  def handle_call({:add_pre_set_parameters_callback, callback}, _from, state) do
    new_callbacks = state.pre_set_parameters_callbacks ++ [callback]
    new_state = %{state | pre_set_parameters_callbacks: new_callbacks}
    {:reply, :ok, new_state}
  end

  def handle_call({:remove_pre_set_parameters_callback, callback}, _from, state) do
    new_callbacks = List.delete(state.pre_set_parameters_callbacks, callback)
    new_state = %{state | pre_set_parameters_callbacks: new_callbacks}
    {:reply, :ok, new_state}
  end

  def handle_call({:add_on_set_parameters_callback, callback}, _from, state) do
    new_callbacks = state.on_set_parameters_callbacks ++ [callback]
    new_state = %{state | on_set_parameters_callbacks: new_callbacks}
    {:reply, :ok, new_state}
  end

  def handle_call({:remove_on_set_parameters_callback, callback}, _from, state) do
    new_callbacks = List.delete(state.on_set_parameters_callbacks, callback)
    new_state = %{state | on_set_parameters_callbacks: new_callbacks}
    {:reply, :ok, new_state}
  end

  def handle_call({:add_post_set_parameters_callback, callback}, _from, state) do
    new_callbacks = state.post_set_parameters_callbacks ++ [callback]
    new_state = %{state | post_set_parameters_callbacks: new_callbacks}
    {:reply, :ok, new_state}
  end

  def handle_call({:remove_post_set_parameters_callback, callback}, _from, state) do
    new_callbacks = List.delete(state.post_set_parameters_callbacks, callback)
    new_state = %{state | post_set_parameters_callbacks: new_callbacks}
    {:reply, :ok, new_state}
  end

  # Helper functions
  defp do_handle_set_parameter_resolved(resolved_name, resolved_value, state) do
    if Map.has_key?(state.parameters, resolved_name) do
      do_set_declared_parameter(resolved_name, resolved_value, state)
    else
      {:reply, {:error, :not_declared}, state}
    end
  end

  defp do_set_declared_parameter(resolved_name, resolved_value, state) do
    {results, changed_parameters, _new_descriptors, _changed_descriptors, new_state} =
      set_one_parameter(resolved_name, resolved_value, [], %{}, [], [], state)

    case results do
      [%{successful: true}] ->
        if state.parameter_event_publisher do
          publish_parameter_event(state.name, state.namespace, %{}, changed_parameters, %{})
        end

        {:reply, :ok, new_state}

      [%{successful: false, reason: reason}] ->
        {:reply, {:error, reason}, state}

      _ ->
        {:reply, {:error, :set_failed}, state}
    end
  end

  defp process_set_parameters_with_convert(processed_parameters, state) do
    undeclared =
      Enum.filter(processed_parameters, fn {name, _value} ->
        not Map.has_key?(state.parameters, name)
      end)

    case undeclared do
      [] ->
        process_declared_parameters_with_convert(processed_parameters, state)

      _ ->
        undeclared_names = Enum.map(undeclared, &elem(&1, 0))
        {:reply, {:error, {:undeclared_parameters, undeclared_names}}, state}
    end
  end

  defp process_declared_parameters_with_convert(processed_parameters, state) do
    invalid_updates =
      Enum.filter(processed_parameters, fn {name, new_value} ->
        case validate_parameter_update(state, name, new_value) do
          :ok -> false
          {:error, _reason} -> true
        end
      end)

    case invalid_updates do
      [] ->
        apply_parameter_updates(processed_parameters, state)

      _ ->
        update_errors =
          Enum.map(invalid_updates, fn {name, new_value} ->
            {:error, reason} = validate_parameter_update(state, name, new_value)
            {name, reason}
          end)

        {:reply, {:error, {:invalid_parameters, update_errors}}, state}
    end
  end

  defp apply_parameter_updates(processed_parameters, state) do
    {updated_parameters, changed_parameters, changes} =
      Enum.reduce(processed_parameters, {state.parameters, %{}, []}, fn {name, new_value},
                                                                        {params, changed, changes} ->
        old_value = Map.get(state.parameters, name)

        {
          Map.put(params, name, new_value),
          Map.put(changed, name, new_value),
          [{name, new_value, old_value} | changes]
        }
      end)

    new_state = %{state | parameters: updated_parameters}

    Enum.each(changes, fn {name, new_value, old_value} ->
      notify_parameter_callbacks(state.post_set_parameters_callbacks, name, new_value, old_value)
    end)

    if state.parameter_event_publisher do
      publish_parameter_event(state.name, state.namespace, %{}, changed_parameters, %{})
    end

    {:reply, :ok, new_state}
  end

  defp convert_parameters_for_set(parameters, false, _state), do: parameters

  defp convert_parameters_for_set(parameters, true, state) do
    Enum.map(parameters, fn {parameter_name, value} ->
      parameter_type =
        case Map.get(state.parameter_descriptors, parameter_name) do
          nil ->
            :undefined

          descriptor ->
            ros2_to_parameter_type(descriptor.type)
        end

      parameter_value =
        if is_map(value) and Map.has_key?(value, :type) do
          value
        else
          gen_parameter_value_struct(value, parameter_type)
        end

      {parameter_name, parameter_value}
    end)
  end

  defp apply_pre_set_parameter_callbacks(callbacks, parameters) do
    Enum.reduce(callbacks, parameters, fn callback, acc_parameters ->
      try do
        case callback.(acc_parameters) do
          updated when is_list(updated) -> updated
          _ -> acc_parameters
        end
      rescue
        error ->
          Logger.error("Pre-set parameter callback failed: #{inspect(error)}")
          acc_parameters
      end
    end)
  end

  defp run_on_set_parameter_callbacks(callbacks, parameters) do
    Enum.reduce_while(callbacks, :ok, fn callback, _acc ->
      callback_result =
        try do
          normalize_on_set_callback_result(callback.(parameters))
        rescue
          error ->
            {:error, "on-set callback failed: #{inspect(error)}"}
        end

      case callback_result do
        :ok ->
          {:cont, :ok}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  defp normalize_on_set_callback_result(result) do
    cond do
      result == :ok ->
        :ok

      result == true ->
        :ok

      result == false ->
        {:error, "rejected by on-set callback"}

      match?(%{successful: true}, result) ->
        :ok

      match?(%{successful: false}, result) ->
        {:error, Map.get(result, :reason, "rejected by on-set callback")}

      match?({:error, _reason}, result) ->
        {:error, elem(result, 1)}

      true ->
        :ok
    end
  end

  defp notify_parameter_callbacks(callbacks, parameter_name, new_param_value, old_param_value) do
    new_value = parameter_value_to_elixir(new_param_value)
    old_value = parameter_value_to_elixir(old_param_value)

    # Notify each callback about the parameter change
    Enum.each(callbacks, fn callback ->
      try do
        callback.(parameter_name, new_value, old_value)
      rescue
        error ->
          require Logger
          Logger.error("Parameter callback failed: #{inspect(error)}")
      end
    end)
  end

  defp set_one_parameter(
         parameter_name,
         new_param_value,
         results,
         changed_parameters,
         new_descriptors,
         changed_descriptors,
         state
       ) do
    case Map.get(state.parameters, parameter_name) do
      nil ->
        new_results = results ++ [gen_set_parameters_result_struct(false, "not declared")]

        {new_results, changed_parameters, new_descriptors, changed_descriptors, state}

      old_param_value ->
        case validate_parameter_update(state, parameter_name, new_param_value) do
          {:error, reason} ->
            new_results = results ++ [gen_set_parameters_result_struct(false, reason)]

            {new_results, changed_parameters, new_descriptors, changed_descriptors, state}

          :ok ->
            parameter_descriptor = Map.fetch!(state.parameter_descriptors, parameter_name)

            updated_parameters = Map.put(state.parameters, parameter_name, new_param_value)

            new_changed_descriptor =
              Map.put(
                parameter_descriptor,
                :type,
                new_param_value.type
              )

            new_state = %{
              state
              | parameters: updated_parameters,
                parameter_descriptors:
                  Map.put(
                    state.parameter_descriptors,
                    parameter_name,
                    new_changed_descriptor
                  )
            }

            new_changed_descriptors = changed_descriptors ++ [new_changed_descriptor]
            new_changed_parameters = Map.put(changed_parameters, parameter_name, new_param_value)

            # Notify callbacks about parameter change
            notify_parameter_callbacks(
              new_state.post_set_parameters_callbacks,
              parameter_name,
              new_param_value,
              old_param_value
            )

            new_results = results ++ [gen_set_parameters_result_struct(true, "")]

            {new_results, new_changed_parameters, new_descriptors, new_changed_descriptors,
             new_state}
        end
    end
  end

  defp validate_parameter_update(state, parameter_name, new_param_value) do
    parameter_descriptor = Map.fetch!(state.parameter_descriptors, parameter_name)

    cond do
      parameter_descriptor.read_only ->
        {:error, "read only"}

      parameter_descriptor.dynamic_typing ->
        :ok

      parameter_descriptor.type == new_param_value.type ->
        :ok

      true ->
        {:error, "wrong parameter type"}
    end
  end

  defp publish_parameter_event_descriptors(
         node_name,
         node_namespace,
         new_parameter_structs,
         changed_parameter_structs,
         deleted_parameter_structs
       ) do
    try do
      # Create parameter event descriptors
      event_descriptors =
        gen_parameter_event_descriptors_struct(
          new_parameter_structs,
          changed_parameter_structs,
          deleted_parameter_structs
        )

      # Publish the event
      Rclex.publish(event_descriptors, @parameter_event_descriptors_topic, node_name,
        namespace: node_namespace
      )
    rescue
      error ->
        require Logger
        Logger.warning("Failed to publish parameter event descriptors: #{inspect(error)}")
    end
  end

  defp publish_parameter_event(
         node_name,
         node_namespace,
         new_params,
         changed_params,
         deleted_params
       ) do
    try do
      # Create timestamp
      now = System.os_time(:nanosecond)
      stamp = gen_time_struct(now)
      full_node_name = "#{node_namespace}#{node_name}"

      # Convert parameters to Parameter structs
      convert_params = fn params ->
        Enum.map(params, fn {name, param_value} ->
          gen_parameter_struct(name, param_value)
        end)
      end

      new_parameter_structs = convert_params.(new_params)
      changed_parameter_structs = convert_params.(changed_params)
      deleted_parameter_structs = convert_params.(deleted_params)

      # Create parameter event
      event =
        gen_parameter_event_struct(
          full_node_name,
          stamp,
          new_parameter_structs,
          changed_parameter_structs,
          deleted_parameter_structs
        )

      # Publish the event
      Rclex.publish(event, @parameter_events_topic, node_name, namespace: node_namespace)
    rescue
      error ->
        require Logger
        Logger.warning("Failed to publish parameter event: #{inspect(error)}")
    end
  end
end
