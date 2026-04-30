defmodule Rclex.ClockTest do
  use ExUnit.Case

  import ExUnit.CaptureLog

  alias Rclex.{Clock, Time}

  setup do
    capture_log(fn -> Application.stop(:rclex) end)
    :ok = Application.ensure_started(:rclex)
    :ok
  end

  describe "system / steady clocks" do
    test "now/1 returns a Time of the configured clock_type" do
      {:ok, pid} = Clock.start_link(clock_type: :steady_time, name: :test_steady)
      assert %Time{clock_type: :steady_time, nanoseconds: ns} = Clock.now(:test_steady)
      assert is_integer(ns) and ns > 0
      :ok = GenServer.stop(pid)
    end

    test "now/1 monotonically increases on a steady clock" do
      {:ok, pid} = Clock.start_link(clock_type: :steady_time, name: :test_steady_mono)
      a = Clock.now(:test_steady_mono)
      Process.sleep(2)
      b = Clock.now(:test_steady_mono)
      assert Time.compare(b, a) in [:gt, :eq]
      :ok = GenServer.stop(pid)
    end

    test "ros_time override on non-ros_time clock returns error" do
      {:ok, pid} = Clock.start_link(clock_type: :system_time, name: :test_sys)
      assert {:error, :clock_type_not_ros_time} = Clock.enable_ros_time_override(:test_sys)
      :ok = GenServer.stop(pid)
    end
  end

  describe "ros_time clock with override" do
    test "set_ros_time_override drives now/1" do
      {:ok, pid} = Clock.start_link(clock_type: :ros_time, name: :test_ros)
      assert :ok = Clock.enable_ros_time_override(:test_ros)
      assert Clock.ros_time_override_active?(:test_ros)
      assert :ok = Clock.set_ros_time_override(:test_ros, Time.new(1_234_567_890, :ros_time))
      assert %Time{nanoseconds: 1_234_567_890, clock_type: :ros_time} =
               Clock.now(:test_ros)
      :ok = GenServer.stop(pid)
    end

    test "disable_ros_time_override clears override flag" do
      {:ok, pid} = Clock.start_link(clock_type: :ros_time, name: :test_ros2)
      :ok = Clock.enable_ros_time_override(:test_ros2)
      :ok = Clock.disable_ros_time_override(:test_ros2)
      refute Clock.ros_time_override_active?(:test_ros2)
      :ok = GenServer.stop(pid)
    end
  end

  describe "Rclex public API helpers" do
    test "start_clock/stop_clock/now via Rclex" do
      assert :ok = Rclex.start_clock(clock_type: :steady_time, name: :api_clock)
      assert %Time{} = Rclex.now(:api_clock)
      assert :ok = Rclex.stop_clock(:api_clock)
    end
  end
end
