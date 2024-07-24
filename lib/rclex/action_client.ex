defmodule Rclex.ActionClient do
  @moduledoc false

  use GenServer, restart: :temporary

  require Logger

  alias Rclex.Nif

  def start_link(args) do
    action_type = Keyword.fetch!(args, :action_type)
    action_name = Keyword.fetch!(args, :action_name)
    name = Keyword.fetch!(args, :name)
    ns = Keyword.fetch!(args, :namespace)

    GenServer.start_link(__MODULE__, args, name: name(action_type, action_name, name, ns))
  end

  def name(action_type, action_name, name, namespace \\ "/") do
    {:global, {:action_client, action_type, action_name, name, namespace}}
  end

  def send_goal_async(%request_type{} = goal, action_name, name, namespace \\ "/") do
    action_type =
      String.to_existing_atom(String.trim_trailing(to_string(request_type), ".Goal"))

    case GenServer.whereis(name(action_type, action_name, name, namespace)) do
      nil -> {:error, :not_found}
      {_atom, _node} -> raise("should not happen")
      pid -> GenServer.call(pid, {:send_goal_async, goal})
    end
  end

  def get_result_async(%request_type{} = goal_handle, action_name, name, namespace \\ "/") do
    action_type =
      String.to_existing_atom(String.trim_trailing(to_string(request_type), ".SendGoal.Request"))

    case GenServer.whereis(name(action_type, action_name, name, namespace)) do
      nil -> {:error, :not_found}
      {_atom, _node} -> raise("should not happen")
      pid -> GenServer.call(pid, {:get_result_async, goal_handle})
    end
  end

  def action_server_available?(action_type, action_name, name, namespace \\ "/") do
    case GenServer.whereis(name(action_type, action_name, name, namespace)) do
      nil -> {:error, :not_found}
      {_atom, _node} -> raise("should not happen")
      pid -> GenServer.call(pid, {:action_server_available})
    end
  end

  # callbacks

  def init(args) do
    Process.flag(:trap_exit, true)

    context = Keyword.fetch!(args, :context)
    node = Keyword.fetch!(args, :node)
    action_type = Keyword.fetch!(args, :action_type)
    action_name = Keyword.fetch!(args, :action_name)
    name = Keyword.fetch!(args, :name)
    namespace = Keyword.fetch!(args, :namespace)

    goal_service_qos = Keyword.get(args, :goal_service_qos, Rclex.QoS.profile_services_default())

    result_service_qos =
      Keyword.get(args, :result_service_qos, Rclex.QoS.profile_services_default())

    cancel_service_qos =
      Keyword.get(args, :cancel_service_qos, Rclex.QoS.profile_services_default())

    feedback_topic_qos = Keyword.get(args, :feedback_topic_qos, Rclex.QoS.profile_default())
    status_topic_qos = Keyword.get(args, :status_topic_qos, Rclex.QoS.profile_status_default())

    type_support = apply(action_type, :type_support!, [])

    action_client =
      Nif.rcl_action_client_init!(
        node,
        type_support,
        ~c"#{action_name}",
        goal_service_qos,
        result_service_qos,
        cancel_service_qos,
        feedback_topic_qos,
        status_topic_qos
      )

    {:ok,
     %{
       node: node,
       context: context,
       action_client: action_client,
       action_type: action_type,
       action_name: action_name,
       name: name,
       namespace: namespace,
       # request_type: apply(service_type, :request_type, []),
       # response_type: apply(service_type, :response_type, []),
       cancel_client_callback_resource: nil,
       feedback_subscription_callback_resource: nil,
       goal_client_callback_resource: nil,
       result_client_callback_resource: nil,
       status_subscription_callback_resource: nil,
       requests: %{}
     }, {:continue, nil}}
  end

  def terminate(
        reason,
        %{
          node: node,
          action_client: ac,
          cancel_client_callback_resource: cancel_client_cr,
          feedback_subscription_callback_resource: feedback_subscription_cr,
          goal_client_callback_resource: goal_client_cr,
          result_client_callback_resource: result_client_cr,
          status_subscription_callback_resource: status_subscription_cr
        } = state
      ) do
    Nif.rcl_action_client_clear_cancel_client_callback!(ac, cancel_client_cr)
    Nif.rcl_action_client_clear_feedback_subscription_callback!(ac, feedback_subscription_cr)
    Nif.rcl_action_client_clear_goal_client_callback!(ac, goal_client_cr)
    Nif.rcl_action_client_clear_result_client_callback!(ac, result_client_cr)
    Nif.rcl_action_client_clear_status_subscription_callback!(ac, status_subscription_cr)
    Nif.rcl_action_client_fini!(ac, node)

    Logger.debug("#{__MODULE__}: #{inspect(reason)} #{Path.join(state.namespace, state.name)}")
  end

  def handle_continue(nil, %{action_client: action_client} = state) do
    cancel_client_callback_resource =
      Nif.rcl_action_client_set_cancel_client_callback!(action_client)

    feedback_subscription_callback_resource =
      Nif.rcl_action_client_set_feedback_subscription_callback!(action_client)

    goal_client_callback_resource = Nif.rcl_action_client_set_goal_client_callback!(action_client)

    result_client_callback_resource =
      Nif.rcl_action_client_set_result_client_callback!(action_client)

    status_subscription_callback_resource =
      Nif.rcl_action_client_set_status_subscription_callback!(action_client)

    {:noreply,
     %{
       state
       | cancel_client_callback_resource: cancel_client_callback_resource,
         feedback_subscription_callback_resource: feedback_subscription_callback_resource,
         goal_client_callback_resource: goal_client_callback_resource,
         result_client_callback_resource: result_client_callback_resource,
         status_subscription_callback_resource: status_subscription_callback_resource
     }}
  end

  def handle_call(
        {:send_goal_async, goal_struct},
        _from,
        %{
          action_client: action_client,
          action_type: action_type,
          requests: requests
        } = state
      ) do
    request_type = apply(action_type, :send_goal_request_type, [])
    request_struct = gen_send_goal_request_struct(request_type, goal_struct)
    request_message = apply(request_type, :create!, [])

    {:ok, sequence_number} =
      try do
        :ok = apply(request_type, :set!, [request_message, request_struct])
        Nif.rcl_action_send_goal_request!(action_client, request_message)
      after
        :ok = apply(request_type, :destroy!, [request_message])
      end

    requests = Map.put_new(requests, sequence_number, request_struct)
    {:reply, :ok, Map.put(state, :requests, requests)}
  end

  def handle_call(
        {:action_server_available},
        _from,
        %{
          node: node,
          action_client: action_client
        } = state
      ) do
    is_available = Nif.rcl_action_server_is_available!(node, action_client)
    {:reply, is_available, state}
  end

  def handle_info(
        {:new_response, number_of_events},
        %{
          client: client,
          callback: callback,
          response_type: response_type,
          requests: requests
        } = state
      )
      when number_of_events > 0 do
    requests =
      Enum.reduce(1..number_of_events, requests, fn _i, requests ->
        response_message = apply(response_type, :create!, [])

        try do
          {:ok, response_sequence_number} =
            Nif.rcl_take_response_with_info!(client, response_message)

          response_struct = apply(response_type, :get!, [response_message])

          {request_struct, requests} = Map.pop(requests, response_sequence_number)

          if request_struct do
            {:ok, _pid} =
              Task.Supervisor.start_child(
                {:via, PartitionSupervisor, {Rclex.TaskSupervisors, self()}},
                fn ->
                  callback.(request_struct, response_struct)
                end
              )
          end

          requests
        after
          :ok = apply(response_type, :destroy!, [response_message])
        end
      end)

    {:noreply, Map.put(state, :requests, requests)}
  end

  defp gen_send_goal_request_struct(request_type, goal_struct) do
    request_struct = struct(request_type)
    %{request_struct|goal: goal_struct, goal_id: gen_uuid_struct()}
  end

  defp gen_uuid_struct() do
    unix_time = DateTime.utc_now() |> DateTime.to_unix()
    <<_r0::32, r1::16, _r2::4, r3::12, _r4::2, r5::62>> = :crypto.strong_rand_bytes(16)
    uuid_struct = struct(Rclex.Pkgs.UniqueIdentifierMsgs.Msg.UUID)
    %{uuid_struct|uuid: <<unix_time::32, r1::16, 4::4, r3::12, 2::2, r5::62>>}
  end

end
