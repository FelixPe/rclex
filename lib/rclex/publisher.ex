defmodule Rclex.Publisher do
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
    {:global, {:publisher, message_type, topic_name, name, namespace}}
  end

  def publish(%message_type{} = message, topic_name, name, namespace \\ "/") do
    case GenServer.whereis(name(message_type, topic_name, name, namespace)) do
      nil -> {:error, :not_found}
      {_atom, _node} -> raise("should not happen")
      pid -> GenServer.call(pid, {:publish, message})
    end
  end

  # callbacks

  def init(args) do
    Process.flag(:trap_exit, true)

    node = Keyword.fetch!(args, :node)
    message_type = Keyword.fetch!(args, :message_type)
    topic_name = Keyword.fetch!(args, :topic_name)
    name = Keyword.fetch!(args, :name)
    namespace = Keyword.fetch!(args, :namespace)
    qos = Keyword.get(args, :qos, Rclex.QoS.profile_default())

    type_support = apply(message_type, :type_support!, [])
    publisher = Nif.rcl_publisher_init!(node, type_support, ~c"#{topic_name}", qos)

    loan_messages =
      Keyword.get(args, :loan_messages, true) and Nif.rcl_publisher_can_loan_messages!(publisher)

    {:ok,
     %{
       node: node,
       publisher: publisher,
       message_type: message_type,
       topic_name: topic_name,
       name: name,
       namespace: namespace,
       loan_messages: loan_messages,
       type_support: type_support
     }}
  end

  def terminate(
        reason,
        %{publisher: publisher, node: node, name: name, namespace: namespace} = _state
      ) do
    Nif.rcl_publisher_fini!(publisher, node)

    Logger.debug("#{__MODULE__}: #{inspect(reason)} #{Path.join(namespace, name)}")
  end

  def handle_call(
        {:publish, data},
        _from,
        %{loan_messages: false, publisher: publisher, message_type: message_type} = state
      ) do
    message = apply(message_type, :create!, [])

    try do
      :ok = apply(message_type, :set!, [message, data])
      :ok = Nif.rcl_publish!(publisher, message)
    after
      :ok = apply(message_type, :destroy!, [message])
    end

    {:reply, :ok, state}
  end

  def handle_call(
        {:publish, data},
        _from,
        %{
          loan_messages: true,
          publisher: publisher,
          message_type: message_type,
          type_support: type_support
        } = state
      ) do
    message = Nif.rcl_borrow_loaned_message!(publisher, type_support)

    try do
      :ok = apply(message_type, :set!, [message, data])
      :ok = Nif.rcl_publish_loaned_message!(publisher, message)
    after
      :ok = Nif.rcl_return_loaned_message_from_publisher!(publisher, message)
    end

    {:reply, :ok, state}
  end
end
