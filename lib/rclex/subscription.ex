defmodule Rclex.Subscription do
  @moduledoc false

  use GenServer, restart: :temporary

  require Logger

  alias Rclex.Nif

  def start_link(args) do
    message_type = Keyword.fetch!(args, :message_type)
    topic_name = Keyword.fetch!(args, :topic_name)
    name = Keyword.fetch!(args, :name)
    namespace = Keyword.fetch!(args, :namespace)

    GenServer.start_link(__MODULE__, args, name: name(message_type, topic_name, name, namespace))
  end

  def name(message_type, topic_name, name, namespace \\ "/") do
    {:global, {:subscription, message_type, topic_name, name, namespace}}
  end

  # callbacks

  def init(args) do
    Process.flag(:trap_exit, true)

    context = Keyword.fetch!(args, :context)
    node = Keyword.fetch!(args, :node)
    message_type = Keyword.fetch!(args, :message_type)
    topic_name = Keyword.fetch!(args, :topic_name)
    callback = Keyword.fetch!(args, :callback)
    name = Keyword.fetch!(args, :name)
    namespace = Keyword.fetch!(args, :namespace)
    qos = Keyword.get(args, :qos, Rclex.QoS.profile_default())

    1 = :erlang.fun_info(callback)[:arity]

    type_support = apply(message_type, :type_support!, [])
    subscription = Nif.rcl_subscription_init!(node, type_support, ~c"#{topic_name}", qos)

    loan_messages =
      Keyword.get(args, :loan_messages, true) and
        Nif.rcl_subscription_can_loan_messages!(subscription)

    wait_set = Nif.rcl_wait_set_init_subscription!(context)

    send(self(), :take)

    {:ok,
     %{
       node: node,
       message_type: message_type,
       topic_name: topic_name,
       callback: callback,
       name: name,
       namespace: namespace,
       subscription: subscription,
       wait_set: wait_set,
       loan_messages: loan_messages
     }}
  end

  def terminate(
        reason,
        %{
          node: node,
          subscription: subscription,
          namespace: namespace,
          name: name,
          wait_set: wait_set
        } = _state
      ) do
    Nif.rcl_wait_set_fini!(wait_set)
    Nif.rcl_subscription_fini!(subscription, node)

    Logger.debug("#{__MODULE__}: #{inspect(reason)} #{Path.join(namespace, name)}")
  end

  def handle_info(
        :take,
        %{
          loan_messages: false,
          subscription: subscription,
          wait_set: wait_set,
          message_type: message_type,
          callback: callback
        } = state
      ) do
    case Nif.rcl_wait_subscription!(wait_set, 1000, subscription) do
      :ok ->
        message = apply(message_type, :create!, [])

        try do
          case Nif.rcl_take!(subscription, message) do
            :ok ->
              message_struct = apply(message_type, :get!, [message])

              {:ok, _pid} =
                Task.Supervisor.start_child(
                  {:via, PartitionSupervisor, {Rclex.TaskSupervisors, self()}},
                  fn -> callback.(message_struct) end
                )

            :error ->
              Logger.error("#{__MODULE__}: take failed but no error occurred in the middleware")
          end
        after
          :ok = apply(message_type, :destroy!, [message])
        end

      :timeout ->
        nil
    end

    send(self(), :take)

    {:noreply, state}
  end

  def handle_info(
        :take,
        %{
          loan_messages: true,
          subscription: subscription,
          wait_set: wait_set,
          message_type: message_type,
          callback: callback
        } = state
      ) do
    case Nif.rcl_wait_subscription!(wait_set, 1000, subscription) do
      :ok ->
        case Nif.rcl_take_loaned_message!(subscription) do
          :error ->
            Logger.error("#{__MODULE__}: take failed but no error occurred in the middleware")

          {:ok, message} ->
            message_struct = apply(message_type, :get!, [message])
            :ok = Nif.rcl_return_loaned_message_from_subscription!(subscription, message)

            {:ok, _pid} =
              Task.Supervisor.start_child(
                {:via, PartitionSupervisor, {Rclex.TaskSupervisors, self()}},
                fn -> callback.(message_struct) end
              )
        end

      :timeout ->
        nil
    end

    send(self(), :take)

    {:noreply, state}
  end
end
