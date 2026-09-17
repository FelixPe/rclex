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

  # bounds how many callbacks run concurrently per batch of taken messages
  @default_max_concurrency System.schedulers_online()
  # kills a single stuck callback rather than blocking the whole batch forever
  @default_callback_timeout 5_000

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
    max_concurrency = Keyword.get(args, :max_concurrency, @default_max_concurrency)
    callback_timeout = Keyword.get(args, :callback_timeout, @default_callback_timeout)
    inline_callback = Keyword.get(args, :inline_callback, false)
    latest_only = Keyword.get(args, :latest_only, false)

    arity = :erlang.fun_info(callback)[:arity]

    unless arity in [1, 2] do
      raise ArgumentError,
            "subscription callback must take 1 (msg) or 2 (msg, info) arguments, got arity #{arity}"
    end

    type_support = apply(message_type, :type_support!, [])
    subscription = Nif.rcl_subscription_init!(node, type_support, ~c"#{topic_name}", qos)

    {:ok,
     %{
       context: context,
       node: node,
       message_type: message_type,
       topic_name: topic_name,
       callback: callback,
       callback_arity: arity,
       name: name,
       namespace: namespace,
       subscription: subscription,
       callback_resource: nil,
       max_concurrency: max_concurrency,
       callback_timeout: callback_timeout,
       inline_callback: inline_callback,
       latest_only: latest_only
     }, {:continue, nil}}
  end

  def terminate(reason, state) do
    Nif.rcl_subscription_clear_message_callback!(state.subscription, state.callback_resource)
    Nif.rcl_subscription_fini!(state.subscription, state.node)

    Logger.debug("#{__MODULE__}: #{inspect(reason)} #{Path.join(state.namespace, state.name)}")
  end

  def handle_continue(nil, state) do
    callback_resource = Nif.rcl_subscription_set_on_new_message_callback!(state.subscription)
    {:noreply, %{state | callback_resource: callback_resource}}
  end

  def handle_info({:new_message, number_of_events}, state) when number_of_events > 0 do
    cond do
      state.latest_only ->
        drain_notifications()
        take_latest_and_invoke(state)

      state.inline_callback ->
        Enum.each(1..number_of_events, fn _ -> take_and_invoke_one(state) end)

      true ->
        1..number_of_events
        |> Enum.reduce([], fn _, acc -> take_one(state, acc) end)
        |> dispatch_all(state)
    end

    {:noreply, state}
  end

  # Drain notifications already queued in this subscription process before taking
  # the newest available sample.
  defp drain_notifications do
    receive do
      {:new_message, n} when n > 0 -> drain_notifications()
    after
      0 -> :ok
    end
  end

  # Reuse one native message buffer so superseded samples are overwritten by
  # rcl_take and are never converted into Elixir structs.
  defp take_latest_and_invoke(state) do
    message = apply(state.message_type, :create!, [])

    try do
      case take_until_empty(state, message, :empty) do
        :empty ->
          :ok

        {:taken, message_info} ->
          message_struct = apply(state.message_type, :get!, [message])
          invoke_callback_safely(state, message_struct, message_info)
      end
    after
      :ok = apply(state.message_type, :destroy!, [message])
    end
  end

  defp take_until_empty(state, message, last) do
    case take(state, message) do
      :subscription_take_failed -> last
      :ok -> take_until_empty(state, message, {:taken, nil})
      {:ok, message_info} -> take_until_empty(state, message, {:taken, message_info})
    end
  end

  defp take_and_invoke_one(state) do
    case take_one(state, []) do
      [{message_struct, message_info}] ->
        invoke_callback_safely(state, message_struct, message_info)

      [] ->
        :ok
    end
  end

  defp take_one(state, acc) do
    message = apply(state.message_type, :create!, [])

    try do
      case take(state, message) do
        {:ok, message_info} ->
          [{apply(state.message_type, :get!, [message]), message_info} | acc]

        :ok ->
          [{apply(state.message_type, :get!, [message]), nil} | acc]

        :subscription_take_failed ->
          Logger.debug("#{__MODULE__}: take failed but no error occurred in the middleware")
          acc
      end
    after
      :ok = apply(state.message_type, :destroy!, [message])
    end
  end

  defp take(%{callback_arity: 2} = state, message) do
    Nif.rcl_take_with_info!(state.subscription, message)
  end

  defp take(state, message) do
    Nif.rcl_take!(state.subscription, message)
  end

  defp dispatch_all([], _state), do: :ok

  defp dispatch_all(messages, state) do
    {:via, PartitionSupervisor, {Rclex.TaskSupervisors, self()}}
    |> Task.Supervisor.async_stream_nolink(
      messages,
      fn {message_struct, message_info} ->
        invoke_callback(state, message_struct, message_info)
      end,
      max_concurrency: state.max_concurrency,
      ordered: false,
      timeout: state.callback_timeout,
      on_timeout: :kill_task
    )
    |> Enum.each(&log_callback_result(&1, state))
  end

  defp log_callback_result({:ok, _result}, _state), do: :ok

  defp log_callback_result({:exit, reason}, state) do
    Logger.warning(
      "#{__MODULE__}: callback failed #{Path.join(state.namespace, state.name)} #{inspect(reason)}"
    )
  end

  defp invoke_callback_safely(state, message_struct, message_info) do
    invoke_callback(state, message_struct, message_info)
  rescue
    exception -> log_callback_failure(state, exception, __STACKTRACE__)
  catch
    kind, reason -> log_callback_failure(state, {kind, reason}, __STACKTRACE__)
  end

  defp log_callback_failure(state, reason, stacktrace) do
    Logger.warning(
      "#{__MODULE__}: callback failed #{Path.join(state.namespace, state.name)} " <>
        Exception.format(:error, reason, stacktrace)
    )
  end

  defp invoke_callback(%{callback_arity: 2} = state, message_struct, message_info) do
    state.callback.(message_struct, message_info)
  end

  defp invoke_callback(state, message_struct, _message_info) do
    state.callback.(message_struct)
  end
end
