defmodule Rclex.Duration do
  @moduledoc """
  A signed duration, stored as nanoseconds.

  ROS 2 messages typically carry durations as `builtin_interfaces/msg/Duration`.
  Use `to_msg/1` and `from_msg/1` to convert.
  """

  defstruct nanoseconds: 0

  @type t :: %__MODULE__{nanoseconds: integer()}

  @doc "Create a `Duration` from an integer number of nanoseconds."
  @spec new(integer()) :: t()
  def new(nanoseconds) when is_integer(nanoseconds) do
    %__MODULE__{nanoseconds: nanoseconds}
  end

  @doc "Create a `Duration` from a number of seconds (may be fractional)."
  @spec from_seconds(number()) :: t()
  def from_seconds(seconds) when is_number(seconds) do
    new(round(seconds * 1_000_000_000))
  end

  @doc "Total nanoseconds, possibly negative."
  @spec to_nanoseconds(t()) :: integer()
  def to_nanoseconds(%__MODULE__{nanoseconds: ns}), do: ns

  @doc "Duration in seconds (floating point)."
  @spec to_seconds(t()) :: float()
  def to_seconds(%__MODULE__{nanoseconds: ns}), do: ns / 1_000_000_000

  @doc "Convert to a `Rclex.Pkgs.BuiltinInterfaces.Msg.Duration` struct."
  @spec to_msg(t()) :: struct()
  def to_msg(%__MODULE__{nanoseconds: ns}) do
    sec = div(ns, 1_000_000_000)
    nanosec_signed = rem(ns, 1_000_000_000)

    {sec, nanosec} =
      if nanosec_signed < 0 do
        {sec - 1, nanosec_signed + 1_000_000_000}
      else
        {sec, nanosec_signed}
      end

    struct(Rclex.Pkgs.BuiltinInterfaces.Msg.Duration, %{sec: sec, nanosec: nanosec})
  end

  @doc "Build a `Duration` from a `builtin_interfaces/msg/Duration`-shaped struct or map."
  @spec from_msg(map()) :: t()
  def from_msg(%{sec: sec, nanosec: nanosec}) when is_integer(sec) and is_integer(nanosec) do
    new(sec * 1_000_000_000 + nanosec)
  end

  @doc "Add two durations."
  @spec add(t(), t()) :: t()
  def add(%__MODULE__{nanoseconds: a}, %__MODULE__{nanoseconds: b}), do: new(a + b)

  @doc "Subtract one duration from another."
  @spec sub(t(), t()) :: t()
  def sub(%__MODULE__{nanoseconds: a}, %__MODULE__{nanoseconds: b}), do: new(a - b)

  @doc "Multiply a duration by a numeric scalar."
  @spec mul(t(), number()) :: t()
  def mul(%__MODULE__{nanoseconds: ns}, factor) when is_number(factor) do
    new(round(ns * factor))
  end

  @doc "Negate a duration."
  @spec negate(t()) :: t()
  def negate(%__MODULE__{nanoseconds: ns}), do: new(-ns)

  @doc "Compare two durations; returns `:lt`, `:eq`, or `:gt`."
  @spec compare(t(), t()) :: :lt | :eq | :gt
  def compare(%__MODULE__{nanoseconds: a}, %__MODULE__{nanoseconds: b}) do
    cond do
      a < b -> :lt
      a > b -> :gt
      true -> :eq
    end
  end
end
