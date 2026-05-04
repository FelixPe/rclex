defmodule Rclex.TimeTest do
  use ExUnit.Case, async: true

  alias Rclex.{Time, Duration}
  alias Rclex.Pkgs.BuiltinInterfaces.Msg, as: BI

  describe "new/2 and arithmetic" do
    test "new/2 builds a Time with default :system_time" do
      assert %Time{nanoseconds: 42, clock_type: :system_time} = Time.new(42)
    end

    test "from_seconds/2 rounds to nanoseconds" do
      assert Time.from_seconds(1.5).nanoseconds == 1_500_000_000
      assert Time.from_seconds(0.000_000_001).nanoseconds == 1
    end

    test "to_seconds/1 round-trips" do
      assert Time.to_seconds(Time.from_seconds(1.5)) == 1.5
    end

    test "add/2 adds a Duration" do
      t = Time.new(1_000, :steady_time)
      d = Duration.new(500)
      assert Time.add(t, d) == %Time{nanoseconds: 1_500, clock_type: :steady_time}
    end

    test "sub/2 of two Times yields Duration" do
      a = Time.new(2_000, :steady_time)
      b = Time.new(500, :steady_time)
      assert Time.sub(a, b) == %Duration{nanoseconds: 1_500}
    end

    test "sub/2 raises across clock types" do
      assert_raise ArgumentError, fn ->
        Time.sub(Time.new(0, :steady_time), Time.new(0, :system_time))
      end
    end

    test "sub/2 of Time and Duration yields Time" do
      assert Time.sub(Time.new(1_000, :ros_time), Duration.new(400)) ==
               %Time{nanoseconds: 600, clock_type: :ros_time}
    end

    test "compare/2" do
      assert Time.compare(Time.new(1), Time.new(2)) == :lt
      assert Time.compare(Time.new(2), Time.new(1)) == :gt
      assert Time.compare(Time.new(1), Time.new(1)) == :eq
    end
  end

  describe "msg conversions" do
    test "to_msg/1 produces a BuiltinInterfaces.Msg.Time" do
      assert Time.to_msg(Time.new(1_500_000_001)) ==
               %BI.Time{sec: 1, nanosec: 500_000_001}
    end

    test "from_msg/2 builds a Time from a struct" do
      msg = %BI.Time{sec: 2, nanosec: 250_000_000}

      assert Time.from_msg(msg, :ros_time) ==
               %Time{nanoseconds: 2_250_000_000, clock_type: :ros_time}
    end

    test "to_msg/1 raises for negative nanoseconds" do
      assert_raise ArgumentError, fn -> Time.to_msg(Time.new(-1)) end
    end
  end
end
