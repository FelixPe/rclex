defmodule Rclex.EntitiesSupervisor do
  @moduledoc false

  use DynamicSupervisor

  def start_link(args) do
    name = Keyword.fetch!(args, :name)
    namespace = Keyword.fetch!(args, :namespace)

    DynamicSupervisor.start_link(__MODULE__, args, name: name(name, namespace))
  end

  def name(name, namespace \\ "/") do
    {:global, {:entities_supervisor, name, namespace}}
  end

  def get_local_entities(opts \\ []) when is_list(opts) do
    entity_pids = entity_pids()

    :global.registered_names()
    |> Enum.flat_map(&entity_from_registration(&1, entity_pids))
    |> Enum.filter(&matches_filters?(&1, opts))
  end

  def start_publisher(node, message_type, topic_name, name, namespace, qos) do
    DynamicSupervisor.start_child(
      name(name, namespace),
      {Rclex.Publisher,
       [
         node: node,
         message_type: message_type,
         topic_name: topic_name,
         name: name,
         namespace: namespace,
         qos: qos
       ]}
    )
  end

  def start_subscription(
        context,
        node,
        callback,
        message_type,
        topic_name,
        name,
        namespace,
        qos
      ) do
    DynamicSupervisor.start_child(
      name(name, namespace),
      {Rclex.Subscription,
       [
         context: context,
         node: node,
         callback: callback,
         message_type: message_type,
         topic_name: topic_name,
         name: name,
         namespace: namespace,
         qos: qos
       ]}
    )
  end

  def start_service(context, callback, node, service_type, service_name, name, namespace, qos) do
    DynamicSupervisor.start_child(
      name(name, namespace),
      {Rclex.Service,
       [
         context: context,
         node: node,
         callback: callback,
         service_type: service_type,
         service_name: service_name,
         name: name,
         namespace: namespace,
         qos: qos
       ]}
    )
  end

  def start_client(context, callback, node, service_type, service_name, name, namespace, qos) do
    DynamicSupervisor.start_child(
      name(name, namespace),
      {Rclex.Client,
       [
         context: context,
         callback: callback,
         node: node,
         service_type: service_type,
         service_name: service_name,
         name: name,
         namespace: namespace,
         qos: qos
       ]}
    )
  end

  def start_action_server(
        context,
        {execute_callback, goal_callback, handle_accepted_callback, cancel_callback},
        node,
        action_type,
        action_name,
        name,
        namespace,
        options
      ) do
    DynamicSupervisor.start_child(
      name(name, namespace),
      {Rclex.ActionServer,
       [
         context: context,
         node: node,
         action_type: action_type,
         action_name: action_name,
         name: name,
         namespace: namespace,
         options: options,
         execute_callback: execute_callback,
         goal_callback: goal_callback,
         handle_accepted_callback: handle_accepted_callback,
         cancel_callback: cancel_callback
       ]}
    )
  end

  def start_action_client(
        context,
        node,
        action_type,
        action_name,
        name,
        namespace,
        options
      ) do
    DynamicSupervisor.start_child(
      name(name, namespace),
      {Rclex.ActionClient,
       [
         context: context,
         node: node,
         action_type: action_type,
         action_name: action_name,
         name: name,
         namespace: namespace,
         options: options
       ]}
    )
  end

  def start_timer(context, period_ms, callback, timer_name, name, namespace \\ "/") do
    DynamicSupervisor.start_child(
      name(name, namespace),
      {Rclex.Timer,
       [
         context: context,
         period_ms: period_ms,
         callback: callback,
         timer_name: timer_name,
         name: name,
         namespace: namespace
       ]}
    )
  end

  def stop_publisher(message_type, topic_name, name, namespace) do
    entity_name = Rclex.Publisher.name(message_type, topic_name, name, namespace)
    stop_entity(entity_name, name, namespace)
  end

  def stop_subscription(message_type, topic_name, name, namespace) do
    entity_name = Rclex.Subscription.name(message_type, topic_name, name, namespace)
    stop_entity(entity_name, name, namespace)
  end

  def stop_service(service_type, service_name, name, namespace) do
    entity_name = Rclex.Service.name(service_type, service_name, name, namespace)
    stop_entity(entity_name, name, namespace)
  end

  def stop_client(service_type, service_name, name, namespace) do
    entity_name = Rclex.Client.name(service_type, service_name, name, namespace)
    stop_entity(entity_name, name, namespace)
  end

  def stop_action_server(action_type, action_name, name, namespace) do
    entity_name = Rclex.ActionServer.name(action_type, action_name, name, namespace)
    stop_entity(entity_name, name, namespace)
  end

  def stop_action_client(action_type, action_name, name, namespace) do
    entity_name = Rclex.ActionClient.name(action_type, action_name, name, namespace)
    stop_entity(entity_name, name, namespace)
  end

  def stop_timer(timer_name, name, namespace) do
    entity_name = Rclex.Timer.name(timer_name, name, namespace)
    stop_entity(entity_name, name, namespace)
  end

  defp stop_entity(entity_name, name, namespace) do
    case GenServer.whereis(entity_name) do
      nil -> {:error, :not_found}
      pid -> DynamicSupervisor.terminate_child(name(name, namespace), pid)
    end
  end

  defp entity_pids do
    Rclex.NodesSupervisor.name()
    |> DynamicSupervisor.which_children()
    |> Enum.flat_map(&entity_supervisor_pids/1)
    |> Enum.flat_map(&DynamicSupervisor.which_children/1)
    |> Enum.flat_map(fn {_, pid, _, _} -> if is_pid(pid), do: [pid], else: [] end)
  end

  defp entity_supervisor_pids({_, node_supervisor_pid, _, _}) when is_pid(node_supervisor_pid) do
    node_supervisor_pid
    |> Supervisor.which_children()
    |> Enum.flat_map(fn
      {Rclex.EntitiesSupervisor, pid, _, _} when is_pid(pid) -> [pid]
      _ -> []
    end)
  end

  defp entity_supervisor_pids(_child), do: []

  defp entity_from_registration(
         {entity_type, type, entity_name, name, namespace} = registration,
         entity_pids
       )
       when entity_type in [
              :publisher,
              :subscription,
              :service,
              :client,
              :action_server,
              :action_client
            ] do
    if :global.whereis_name(registration) in entity_pids do
      [
        %{
          name: name,
          namespace: namespace,
          type: type,
          entity_type: entity_type,
          entity_name: entity_name
        }
      ]
    else
      []
    end
  end

  defp entity_from_registration(_registration, _entity_pids), do: []

  defp matches_filters?(entity, opts) do
    Enum.all?(opts, fn {key, value} -> Map.get(entity, key) == value end)
  end

  # callbacks

  def init(_args) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
