defmodule Rclex.LifecycleNodeTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  setup do
    :ok = Application.ensure_started(:rclex)
    on_exit(fn -> capture_log(fn -> Application.stop(:rclex) end) end)
    :ok
  end

  defmodule Plain do
    use Rclex.LifecycleNode
  end

  defmodule Recorder do
    use Rclex.LifecycleNode

    @impl true
    def on_configure(state), do: {:ok, [:configured | state]}
    @impl true
    def on_activate(state), do: {:ok, [:activated | state]}
    @impl true
    def on_deactivate(state), do: {:ok, [:deactivated | state]}
    @impl true
    def on_cleanup(state), do: {:ok, [:cleaned | state]}
    @impl true
    def on_shutdown(state), do: {:ok, [:shut | state]}
  end

  defmodule FailConfigure do
    use Rclex.LifecycleNode

    @impl true
    def on_configure(state), do: {:error, [:fail | state]}
  end

  defmodule RaiseActivate do
    use Rclex.LifecycleNode

    @impl true
    def on_activate(_state), do: raise("boom")
    @impl true
    def on_error(state), do: {:ok, [:on_error | state]}
  end

  defmodule FatalConfigure do
    use Rclex.LifecycleNode

    @impl true
    def on_configure(state), do: {:fatal, [:fatal | state]}
    @impl true
    def on_error(state), do: {:ok, [:on_error | state]}
  end

  describe "state machine" do
    test "starts in :unconfigured and supports the happy path" do
      :ok = Rclex.start_lifecycle_node(Recorder, "lc1", user_state: [])
      assert :unconfigured == Rclex.lifecycle_get_state("lc1")

      assert :ok = Rclex.lifecycle_change_state("lc1", :configure)
      assert :inactive == Rclex.lifecycle_get_state("lc1")

      assert :ok = Rclex.lifecycle_change_state("lc1", :activate)
      assert :active == Rclex.lifecycle_get_state("lc1")

      assert :ok = Rclex.lifecycle_change_state("lc1", :deactivate)
      assert :inactive == Rclex.lifecycle_get_state("lc1")

      assert :ok = Rclex.lifecycle_change_state("lc1", :cleanup)
      assert :unconfigured == Rclex.lifecycle_get_state("lc1")

      user = Rclex.LifecycleNode.get_user_state("lc1")
      assert :configured in user
      assert :activated in user
      assert :deactivated in user
      assert :cleaned in user

      capture_log(fn -> :ok = Rclex.stop_lifecycle_node("lc1") end)
    end

    test "shutdown moves to :finalized from any active state" do
      :ok = Rclex.start_lifecycle_node(Plain, "lc2")
      assert :ok = Rclex.lifecycle_change_state("lc2", :shutdown)
      assert :finalized == Rclex.lifecycle_get_state("lc2")

      # no further transitions allowed
      assert {:error, :invalid_transition} =
               Rclex.lifecycle_change_state("lc2", :configure)

      capture_log(fn -> :ok = Rclex.stop_lifecycle_node("lc2") end)
    end

    test "rejects invalid transitions" do
      :ok = Rclex.start_lifecycle_node(Plain, "lc3")

      assert {:error, :invalid_transition} =
               Rclex.lifecycle_change_state("lc3", :activate)

      assert {:error, :invalid_transition} =
               Rclex.lifecycle_change_state("lc3", :deactivate)

      assert {:error, :invalid_transition} =
               Rclex.lifecycle_change_state("lc3", :cleanup)

      capture_log(fn -> :ok = Rclex.stop_lifecycle_node("lc3") end)
    end

    test "callback returning {:error, _} keeps node in current primary state" do
      :ok = Rclex.start_lifecycle_node(FailConfigure, "lc4", user_state: [])

      assert {:error, :callback_failed} =
               Rclex.lifecycle_change_state("lc4", :configure)

      assert :unconfigured == Rclex.lifecycle_get_state("lc4")
      assert :fail in Rclex.LifecycleNode.get_user_state("lc4")

      capture_log(fn -> :ok = Rclex.stop_lifecycle_node("lc4") end)
    end

    test "raised callback transitions to :finalized via on_error" do
      :ok = Rclex.start_lifecycle_node(RaiseActivate, "lc5", user_state: [])

      assert :ok = Rclex.lifecycle_change_state("lc5", :configure)
      assert :inactive == Rclex.lifecycle_get_state("lc5")

      capture_log(fn ->
        assert {:error, :callback_errored} =
                 Rclex.lifecycle_change_state("lc5", :activate)
      end)

      assert :finalized == Rclex.lifecycle_get_state("lc5")
      assert :on_error in Rclex.LifecycleNode.get_user_state("lc5")

      capture_log(fn -> :ok = Rclex.stop_lifecycle_node("lc5") end)
    end

    test "callback returning {:fatal, _} transitions to :finalized via on_error" do
      :ok = Rclex.start_lifecycle_node(FatalConfigure, "lc6", user_state: [])

      assert {:error, :callback_errored} =
               Rclex.lifecycle_change_state("lc6", :configure)

      assert :finalized == Rclex.lifecycle_get_state("lc6")
      user_state = Rclex.LifecycleNode.get_user_state("lc6")
      assert :fatal in user_state
      assert :on_error in user_state

      capture_log(fn -> :ok = Rclex.stop_lifecycle_node("lc6") end)
    end
  end

  describe "lifecycle service handlers" do
    test "handle_change_state returns false for an unknown transition id" do
      response = Rclex.LifecycleNode.handle_change_state(%{transition: %{id: 999}}, "lc_bad", "/")

      assert %{success: false} = response
    end

    test "handle_get_state returns the current primary state as a State message" do
      :ok = Rclex.start_lifecycle_node(Plain, "lc_svc", namespace: "/test")

      response = Rclex.LifecycleNode.handle_get_state(nil, "lc_svc", "/test")
      assert %{current_state: %{id: 1, label: "unconfigured"}} = response

      :ok = Rclex.lifecycle_change_state("lc_svc", :configure, namespace: "/test")
      response2 = Rclex.LifecycleNode.handle_get_state(nil, "lc_svc", "/test")
      assert %{current_state: %{id: 2, label: "inactive"}} = response2

      capture_log(fn -> :ok = Rclex.stop_lifecycle_node("lc_svc", namespace: "/test") end)
    end

    test "handle_get_available_states returns all four primary states" do
      :ok = Rclex.start_lifecycle_node(Plain, "lc_svc2")

      response = Rclex.LifecycleNode.handle_get_available_states(nil, "lc_svc2", "/")
      ids = Enum.map(response.available_states, & &1.id) |> Enum.sort()
      assert ids == [1, 2, 3, 4]

      capture_log(fn -> :ok = Rclex.stop_lifecycle_node("lc_svc2") end)
    end

    test "handle_get_available_transitions returns transitions for the current state" do
      :ok = Rclex.start_lifecycle_node(Plain, "lc_svc3")

      response = Rclex.LifecycleNode.handle_get_available_transitions(nil, "lc_svc3", "/")

      labels = Enum.map(response.available_transitions, & &1.transition.label) |> Enum.sort()
      assert labels == ["configure", "shutdown"]

      capture_log(fn -> :ok = Rclex.stop_lifecycle_node("lc_svc3") end)
    end
  end
end
