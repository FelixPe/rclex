defmodule Rclex.DurationTest do
  use ExUnit.Case, async: true

  alias Rclex.Duration
  alias Rclex.Pkgs.BuiltinInterfaces.Msg, as: BI

  test "new/1 and to_nanoseconds/1" do
    assert Duration.to_nanoseconds(Duration.new(123)) == 123
  end

  test "from_seconds/1 + to_seconds/1 round-trip" do
    assert Duration.to_seconds(Duration.from_seconds(2.5)) == 2.5
    assert Duration.from_seconds(0.5).nanoseconds == 500_000_000
  end

  test "arithmetic" do
    assert Duration.add(Duration.new(100), Duration.new(50)) == Duration.new(150)
    assert Duration.sub(Duration.new(100), Duration.new(50)) == Duration.new(50)
    assert Duration.mul(Duration.new(100), 2.5) == Duration.new(250)
    assert Duration.negate(Duration.new(100)) == Duration.new(-100)
  end

  test "compare/2" do
    assert Duration.compare(Duration.new(1), Duration.new(2)) == :lt
    assert Duration.compare(Duration.new(2), Duration.new(1)) == :gt
    assert Duration.compare(Duration.new(1), Duration.new(1)) == :eq
  end

  describe "msg conversions" do
    test "to_msg/1 of positive duration" do
      assert Duration.to_msg(Duration.new(2_500_000_000)) ==
               %BI.Duration{sec: 2, nanosec: 500_000_000}
    end

    test "to_msg/1 of negative duration uses normalized nanosec" do
      assert Duration.to_msg(Duration.new(-500_000_000)) ==
               %BI.Duration{sec: -1, nanosec: 500_000_000}
    end

    test "from_msg/1" do
      assert Duration.from_msg(%BI.Duration{sec: 1, nanosec: 250_000_000}) ==
               Duration.new(1_250_000_000)
    end

    test "round-trip preserves negatives" do
      d = Duration.new(-1_750_000_000)
      assert d |> Duration.to_msg() |> Duration.from_msg() == d
    end
  end
end
