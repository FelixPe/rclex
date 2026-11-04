defmodule Rclex.NodeResourceOwner do
  @moduledoc false

  use GenServer, shutdown: :infinity

  require Logger

  alias Rclex.Nif

  def start_link(args) do
    GenServer.start_link(__MODULE__, args,
      name: name(Keyword.fetch!(args, :name), Keyword.fetch!(args, :namespace))
    )
  end

  def name(name, namespace), do: {:global, {:node_resource_owner, name, namespace}}

  def borrow(owner), do: GenServer.call(owner, :borrow, :infinity)

  @impl true
  def init(args) do
    Process.flag(:trap_exit, true)
    context = Keyword.fetch!(args, :context)
    callback = Keyword.get(args, :graph_change_callback)

    if callback && not is_function(callback, 0) do
      raise ArgumentError, "graph_change_callback must expect zero parameters"
    end

    node =
      Nif.rcl_node_init!(
        context,
        ~c"#{Keyword.fetch!(args, :name)}",
        ~c"#{Keyword.fetch!(args, :namespace)}",
        Keyword.get(args, :ros_args, [])
      )

    {:ok,
     %{
       context: context,
       node: node,
       graph_events: is_function(callback, 0),
       borrower: nil,
       wait_thread: nil
     }}
  end

  @impl true
  def handle_call(:borrow, {borrower, _tag}, %{borrower: nil} = state) do
    wait_thread =
      if state.graph_events do
        guard = Nif.rcl_node_get_graph_guard_condition!(state.node)
        Nif.node_start_waitset_thread!(state.context, guard)
      end

    {:reply, state.node, %{state | borrower: borrower, wait_thread: wait_thread}}
  end

  @impl true
  def handle_info({:new_graph_event, _index} = event, state) do
    send(state.borrower, event)
    {:noreply, state}
  end

  def handle_info({:error, reason} = event, state)
      when reason in [:new_graph_event, :adding_to_waitset_failed] do
    send(state.borrower, event)
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, state) do
    stop_wait_thread(state.wait_thread)
    Nif.rcl_node_fini!(state.node)
  end

  defp stop_wait_thread(nil), do: :ok

  defp stop_wait_thread(wait_thread) do
    case Nif.node_stop_waitset_thread!(wait_thread) do
      :ok ->
        :ok

      {:error, :waitset_thread_stopped, reason} ->
        Logger.error(
          "Node graph thread stopped but exit-guard cleanup failed: #{inspect(reason)}"
        )
    end
  end
end
