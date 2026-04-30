defmodule Rclex.Clock do
  @moduledoc """
  GenServer wrapping an `rcl_clock_t` resource.

  A clock is created with one of three types:

    * `:system_time`  — wall-clock (`CLOCK_REALTIME`)
    * `:steady_time`  — monotonic (`CLOCK_MONOTONIC`)
    * `:ros_time`     — ROS time, which may be overridden by simulated time

  When `:ros_time` is used and the time override is enabled (via
  `enable_ros_time_override/1`), `now/1` returns the value most recently
  passed to `set_ros_time_override/2`. This is the mechanism behind
  `use_sim_time` — a `/clock` topic subscriber feeds messages into the
  override.

  Clocks are usually started under the application's main supervision
  tree via `Rclex.start_clock/1`. They can be reused across many
  callers via the registered name.
  """

  use GenServer, restart: :transient

  alias Rclex.{Nif, Time}

  @type clock_type :: Time.clock_type()

  ## ---------- public API ----------

  @doc """
  Start a clock GenServer.

  ### opts

    * `:clock_type` — one of `:system_time` (default), `:steady_time`, `:ros_time`.
    * `:name` — optional registered name. Defaults to `Rclex.Clock`.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc "Stop the clock and release the underlying NIF resource."
  @spec stop(GenServer.server()) :: :ok
  def stop(server \\ __MODULE__) do
    GenServer.stop(server)
  end

  @doc "Return the clock's current time as a `Rclex.Time`."
  @spec now(GenServer.server()) :: Time.t()
  def now(server \\ __MODULE__) do
    GenServer.call(server, :now)
  end

  @doc "Return the configured `t:clock_type/0`."
  @spec clock_type(GenServer.server()) :: clock_type()
  def clock_type(server \\ __MODULE__) do
    GenServer.call(server, :clock_type)
  end

  @doc """
  Whether the clock is `:ros_time` and ROS time override is enabled.

  When `true`, `now/1` returns whatever was last set via
  `set_ros_time_override/2`.
  """
  @spec ros_time_override_active?(GenServer.server()) :: boolean()
  def ros_time_override_active?(server \\ __MODULE__) do
    GenServer.call(server, :ros_time_override_active?)
  end

  @doc """
  Enable ROS time override on a `:ros_time` clock.

  Returns `{:error, :clock_type_not_ros_time}` if the clock isn't `:ros_time`.
  """
  @spec enable_ros_time_override(GenServer.server()) ::
          :ok | {:error, :clock_type_not_ros_time}
  def enable_ros_time_override(server \\ __MODULE__) do
    GenServer.call(server, :enable_ros_time_override)
  end

  @doc "Disable ROS time override; the clock falls back to system time."
  @spec disable_ros_time_override(GenServer.server()) ::
          :ok | {:error, :clock_type_not_ros_time}
  def disable_ros_time_override(server \\ __MODULE__) do
    GenServer.call(server, :disable_ros_time_override)
  end

  @doc """
  Set the ROS time override value on a `:ros_time` clock.

  The clock must already have override enabled via
  `enable_ros_time_override/1`.
  """
  @spec set_ros_time_override(GenServer.server(), Time.t() | integer()) ::
          :ok | {:error, :clock_type_not_ros_time}
  def set_ros_time_override(server \\ __MODULE__, time)

  def set_ros_time_override(server, %Time{nanoseconds: ns}) do
    GenServer.call(server, {:set_ros_time_override, ns})
  end

  def set_ros_time_override(server, ns) when is_integer(ns) do
    GenServer.call(server, {:set_ros_time_override, ns})
  end

  ## ---------- callbacks ----------

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)
    clock_type = Keyword.get(opts, :clock_type, :system_time)

    if clock_type in [:system_time, :steady_time, :ros_time] do
      clock = Nif.rcl_clock_init!(clock_type)
      {:ok, %{clock_type: clock_type, clock: clock, override_enabled: false}}
    else
      {:stop, {:invalid_clock_type, clock_type}}
    end
  end

  @impl true
  def handle_call(:now, _from, state) do
    ns = Nif.rcl_clock_get_now!(state.clock)
    {:reply, Time.new(ns, state.clock_type), state}
  end

  def handle_call(:clock_type, _from, state) do
    {:reply, state.clock_type, state}
  end

  def handle_call(:ros_time_override_active?, _from, state) do
    active = state.clock_type == :ros_time and state.override_enabled
    {:reply, active, state}
  end

  def handle_call(:enable_ros_time_override, _from, %{clock_type: :ros_time} = state) do
    :ok = Nif.rcl_enable_ros_time_override!(state.clock)
    {:reply, :ok, %{state | override_enabled: true}}
  end

  def handle_call(:enable_ros_time_override, _from, state) do
    {:reply, {:error, :clock_type_not_ros_time}, state}
  end

  def handle_call(:disable_ros_time_override, _from, %{clock_type: :ros_time} = state) do
    :ok = Nif.rcl_disable_ros_time_override!(state.clock)
    {:reply, :ok, %{state | override_enabled: false}}
  end

  def handle_call(:disable_ros_time_override, _from, state) do
    {:reply, {:error, :clock_type_not_ros_time}, state}
  end

  def handle_call({:set_ros_time_override, ns}, _from, %{clock_type: :ros_time} = state) do
    :ok = Nif.rcl_set_ros_time_override!(state.clock, ns)
    {:reply, :ok, state}
  end

  def handle_call({:set_ros_time_override, _ns}, _from, state) do
    {:reply, {:error, :clock_type_not_ros_time}, state}
  end

  @impl true
  def terminate(_reason, %{clock: clock}) do
    _ = Nif.rcl_clock_fini!(clock)
    :ok
  end
end
