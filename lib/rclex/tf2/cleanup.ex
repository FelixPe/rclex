defmodule Rclex.Tf2.Cleanup do
  @moduledoc false

  use GenServer, shutdown: :infinity

  alias Rclex.Nif

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  def attach, do: GenServer.call(__MODULE__, :attach, :infinity)
  def buffer_new(cache_time), do: GenServer.call(__MODULE__, {:buffer_new, cache_time})
  def buffer_destroy(resource), do: GenServer.call(__MODULE__, {:buffer_destroy, resource})

  def start_transport(kind, transport, callback \\ nil),
    do: GenServer.call(__MODULE__, {:start_transport, kind, transport, callback})

  def stop_transport(kind, transport),
    do: GenServer.call(__MODULE__, {:stop_transport, kind, transport})

  def register_wait(request, caller),
    do: GenServer.call(__MODULE__, {:register_wait, request, caller})

  def finish_wait(request, result),
    do: GenServer.call(__MODULE__, {:finish_wait, request, result}, :infinity)

  def release, do: GenServer.call(__MODULE__, :release, :infinity)

  @impl true
  def init(_opts) do
    Process.flag(:trap_exit, true)
    {:ok, empty_state()}
  end

  @impl true
  def handle_call(:attach, {owner, _tag}, state) do
    cond do
      state.owner == owner ->
        {:reply, {:ok, self()}, state}

      state.owner && Process.alive?(state.owner) ->
        {:reply, {:error, :owner_alive}, state}

      true ->
        state = cleanup(state)
        {:reply, {:ok, self()}, %{state | owner: owner, monitor: Process.monitor(owner)}}
    end
  end

  def handle_call({:buffer_new, cache_time}, {owner, _tag}, %{owner: owner} = state) do
    case Nif.tf2_buffer_new!(cache_time) do
      {:ok, resource} = result ->
        {:reply, result, %{state | buffers: MapSet.put(state.buffers, resource)}}

      error ->
        {:reply, error, state}
    end
  end

  def handle_call({:buffer_destroy, resource}, {owner, _tag}, %{owner: owner} = state) do
    result = Nif.tf2_buffer_destroy!(resource)
    {:reply, result, %{state | buffers: MapSet.delete(state.buffers, resource)}}
  end

  def handle_call(:release, {owner, _tag}, %{owner: owner} = state) do
    {:reply, :ok, cleanup(state)}
  end

  def handle_call(
        {:start_transport, kind, transport, callback},
        {owner, _tag},
        %{owner: owner} = state
      ) do
    transports = Map.put(state.transports, transport_key(kind, transport), {kind, transport})
    result = call_start(kind, transport, callback)
    {:reply, result, %{state | transports: transports}}
  end

  def handle_call({:stop_transport, kind, transport}, {owner, _tag}, %{owner: owner} = state) do
    result = stop_endpoint(kind, transport)
    transports = Map.delete(state.transports, transport_key(kind, transport))
    {:reply, result, %{state | transports: transports}}
  end

  def handle_call({:register_wait, request, caller}, {owner, _tag}, %{owner: owner} = state) do
    wait = %{caller: caller, monitor: Process.monitor(caller)}
    {:reply, :ok, %{state | waits: Map.put(state.waits, request, wait)}}
  end

  def handle_call({:finish_wait, request, result}, {owner, _tag}, %{owner: owner} = state) do
    {wait, waits} = Map.pop(state.waits, request)
    if wait, do: complete_wait(request, wait, result)
    {:reply, :ok, %{state | waits: waits}}
  end

  def handle_call(_request, _from, state), do: {:reply, {:error, :tf2_shutdown}, state}

  @impl true
  def handle_info({:DOWN, monitor, :process, _pid, _reason}, %{monitor: monitor} = state) do
    {:noreply, cleanup(state)}
  end

  def handle_info({:DOWN, monitor, :process, _pid, _reason}, state) do
    waits = Map.reject(state.waits, fn {_request, wait} -> wait.monitor == monitor end)
    {:noreply, %{state | waits: waits}}
  end

  @impl true
  def terminate(_reason, state) do
    cleanup(state)
    :ok
  end

  defp cleanup(state) do
    Enum.each(state.buffers, &Nif.tf2_buffer_destroy!/1)

    Enum.each(state.waits, fn {request, wait} ->
      complete_wait(request, wait, {:error, :tf2_shutdown})
    end)

    Enum.each(state.transports, fn {_key, {kind, transport}} -> stop_endpoint(kind, transport) end)

    if state.monitor, do: Process.demonitor(state.monitor, [:flush])
    empty_state()
  end

  defp complete_wait(request, wait, result) do
    Process.demonitor(wait.monitor, [:flush])
    if result, do: send(wait.caller, {:tf2_transform, request, result})
  end

  defp call_start(:listener, transport, callback) do
    protect(fn ->
      Rclex.start_subscription(
        callback,
        transport.message_type,
        transport.topic,
        transport.name,
        transport.opts
      )
    end)
  end

  defp call_start(:broadcaster, transport, _callback) do
    protect(fn ->
      Rclex.start_publisher(
        transport.message_type,
        transport.topic,
        transport.name,
        transport.opts
      )
    end)
  end

  def stop_endpoint(:listener, transport) do
    protect(fn ->
      Rclex.stop_subscription(
        transport.message_type,
        transport.topic,
        transport.name,
        transport.opts
      )
    end)
  end

  def stop_endpoint(:broadcaster, transport) do
    protect(fn ->
      Rclex.stop_publisher(
        transport.message_type,
        transport.topic,
        transport.name,
        transport.opts
      )
    end)
  end

  defp protect(function) do
    function.()
  rescue
    exception -> {:error, {exception.__struct__, Exception.message(exception)}}
  catch
    :exit, reason -> {:error, reason}
  end

  defp transport_key(kind, transport) do
    {kind, transport.message_type, transport.topic, transport.name,
     Keyword.get(transport.opts, :namespace, "/")}
  end

  defp empty_state,
    do: %{owner: nil, monitor: nil, buffers: MapSet.new(), transports: %{}, waits: %{}}
end
