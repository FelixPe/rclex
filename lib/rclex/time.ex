defmodule Rclex.Time do
  @moduledoc """
  A point in time, paired with the clock type that produced it.

  Stored as nanoseconds since the clock's epoch. The `:clock_type` field
  matches the `t:Rclex.Clock.clock_type/0` of the clock that produced the
  time and is used to prevent meaningless arithmetic between incompatible
  clocks (e.g. subtracting a steady-time `Time` from a system-time `Time`).

  ROS 2 messages typically carry timestamps as `builtin_interfaces/msg/Time`.
  Use `to_msg/1` and `from_msg/2` to convert.
  """

  alias Rclex.Duration

  defstruct nanoseconds: 0, clock_type: :system_time

  @type clock_type :: :system_time | :steady_time | :ros_time
  @type t :: %__MODULE__{nanoseconds: integer(), clock_type: clock_type()}

  @doc "Create a `Time` from an integer number of nanoseconds."
  @spec new(integer(), clock_type()) :: t()
  def new(nanoseconds, clock_type \\ :system_time)
      when is_integer(nanoseconds) and clock_type in [:system_time, :steady_time, :ros_time] do
    %__MODULE__{nanoseconds: nanoseconds, clock_type: clock_type}
  end

  @doc "Create a `Time` from a number of seconds."
  @spec from_seconds(number(), clock_type()) :: t()
  def from_seconds(seconds, clock_type \\ :system_time) when is_number(seconds) do
    new(round(seconds * 1_000_000_000), clock_type)
  end

  @doc "Total nanoseconds since the clock's epoch."
  @spec to_nanoseconds(t()) :: integer()
  def to_nanoseconds(%__MODULE__{nanoseconds: ns}), do: ns

  @doc "Time in seconds (floating point)."
  @spec to_seconds(t()) :: float()
  def to_seconds(%__MODULE__{nanoseconds: ns}), do: ns / 1_000_000_000

  @doc """
  Convert to a `Rclex.Pkgs.BuiltinInterfaces.Msg.Time` struct.

  Note: ROS message `Time` uses unsigned `nanosec`, so negative `Time` values
  are not representable. Conversion of a negative `Time` raises.
  """
  @spec to_msg(t()) :: struct()
  def to_msg(%__MODULE__{nanoseconds: ns}) when ns >= 0 do
    sec = div(ns, 1_000_000_000)
    nanosec = rem(ns, 1_000_000_000)
    struct(Rclex.Pkgs.BuiltinInterfaces.Msg.Time, %{sec: sec, nanosec: nanosec})
  end

  def to_msg(%__MODULE__{nanoseconds: ns}) do
    raise ArgumentError, "cannot convert negative Time (#{ns} ns) to builtin_interfaces/msg/Time"
  end

  @doc "Build a `Time` from a `builtin_interfaces/msg/Time`-shaped struct or map."
  @spec from_msg(map(), clock_type()) :: t()
  def from_msg(%{sec: sec, nanosec: nanosec}, clock_type \\ :system_time)
      when is_integer(sec) and is_integer(nanosec) do
    new(sec * 1_000_000_000 + nanosec, clock_type)
  end

  @doc "Add a `Duration` to a `Time`, returning a new `Time`."
  @spec add(t(), Duration.t()) :: t()
  def add(%__MODULE__{nanoseconds: ns, clock_type: ct}, %Duration{nanoseconds: dns}) do
    %__MODULE__{nanoseconds: ns + dns, clock_type: ct}
  end

  @doc """
  Subtract a `Time` or `Duration` from a `Time`.

  Subtracting two `Time` values returns a `Duration`. Both must share the
  same `:clock_type`, otherwise raises `ArgumentError`.
  """
  @spec sub(t(), t() | Duration.t()) :: Duration.t() | t()
  def sub(%__MODULE__{clock_type: ct, nanoseconds: a}, %__MODULE__{clock_type: ct, nanoseconds: b}) do
    %Duration{nanoseconds: a - b}
  end

  def sub(%__MODULE__{clock_type: ct1}, %__MODULE__{clock_type: ct2}) do
    raise ArgumentError,
          "cannot subtract Time of clock_type #{inspect(ct2)} from clock_type #{inspect(ct1)}"
  end

  def sub(%__MODULE__{nanoseconds: ns, clock_type: ct}, %Duration{nanoseconds: dns}) do
    %__MODULE__{nanoseconds: ns - dns, clock_type: ct}
  end

  @doc "Compare two `Time` values; returns `:lt`, `:eq`, or `:gt`."
  @spec compare(t(), t()) :: :lt | :eq | :gt
  def compare(%__MODULE__{clock_type: ct, nanoseconds: a}, %__MODULE__{
        clock_type: ct,
        nanoseconds: b
      }) do
    cond do
      a < b -> :lt
      a > b -> :gt
      true -> :eq
    end
  end

  def compare(%__MODULE__{clock_type: ct1}, %__MODULE__{clock_type: ct2}) do
    raise ArgumentError,
          "cannot compare Time of clock_type #{inspect(ct1)} with clock_type #{inspect(ct2)}"
  end
end
