defmodule Rclex.GraphMonitorTest do
  use ExUnit.Case

  import ExUnit.CaptureLog

  alias Rclex.GraphMonitor
  alias Rclex.NodeSupervisor
  alias Rclex.Pkgs.StdMsgs
  alias Rclex.Pkgs.StdSrvs

  setup do
    :ok = Application.ensure_started(:rclex)
    on_exit(fn -> capture_log(fn -> Application.stop(:rclex) end) end)
  end

  describe "start_node/2 with graph_monitor: true" do
    test "starts a GraphMonitor process under the node supervisor" do
      :ok = Rclex.start_node("monitored", graph_monitor: true)

      supervisor_pid = GenServer.whereis(NodeSupervisor.name("monitored"))
      assert is_pid(supervisor_pid)

      children = Supervisor.which_children(supervisor_pid)
      monitor_child = Enum.find(children, fn {mod, _, _, _} -> mod == GraphMonitor end)
      assert monitor_child != nil
      assert is_pid(elem(monitor_child, 1))
    end

    test "does not start a GraphMonitor process without the option" do
      :ok = Rclex.start_node("unmonitored")

      supervisor_pid = GenServer.whereis(NodeSupervisor.name("unmonitored"))
      children = Supervisor.which_children(supervisor_pid)
      monitor_child = Enum.find(children, fn {mod, _, _, _} -> mod == GraphMonitor end)
      assert monitor_child == nil
    end

    test "graph_monitor: true and graph_change_callback can coexist" do
      me = self()
      callback = fn -> send(me, :callback_fired) end

      :ok =
        Rclex.start_node("dual",
          graph_monitor: true,
          graph_change_callback: callback
        )

      assert_receive :callback_fired
    end

    test "GraphMonitor stops cleanly with the node" do
      :ok = Rclex.start_node("stop_test", graph_monitor: true)

      supervisor_pid = GenServer.whereis(NodeSupervisor.name("stop_test"))
      children = Supervisor.which_children(supervisor_pid)

      {GraphMonitor, monitor_pid, _, _} =
        Enum.find(children, fn {m, _, _, _} -> m == GraphMonitor end)

      ref = Process.monitor(monitor_pid)

      capture_log(fn -> :ok = Rclex.stop_node("stop_test") end)

      assert_receive {:DOWN, ^ref, :process, ^monitor_pid, _}
    end
  end

  describe "telemetry availability" do
    test "returns false when the configured telemetry module is unavailable" do
      old_module = Application.get_env(:rclex, :telemetry_module)
      Application.put_env(:rclex, :telemetry_module, :rclex_missing_telemetry)

      on_exit(fn ->
        if is_nil(old_module) do
          Application.delete_env(:rclex, :telemetry_module)
        else
          Application.put_env(:rclex, :telemetry_module, old_module)
        end
      end)

      refute GraphMonitor.telemetry_available?()
    end

    test "does not warn when the configured telemetry module is unavailable" do
      old_module = Application.get_env(:rclex, :telemetry_module)
      Application.put_env(:rclex, :telemetry_module, :rclex_missing_telemetry)
      me = self()

      on_exit(fn ->
        if is_nil(old_module) do
          Application.delete_env(:rclex, :telemetry_module)
        else
          Application.put_env(:rclex, :telemetry_module, old_module)
        end
      end)

      log =
        capture_log(fn ->
          :ok = Rclex.start_node("warn_watcher", graph_monitor: true)

          :ok =
            GraphMonitor.on_entity("warn_watcher", {:node, "warn_joiner", "/"}, fn _ ->
              send(me, :entity_seen)
            end)

          :ok = Rclex.start_node("warn_joiner")
          assert_receive :entity_seen, 5_000
        end)

      refute log =~ "telemetry not available"
    end
  end

  describe "node telemetry" do
    setup [:attach_all_events]

    test "emits node_joined when another node joins the graph" do
      :ok = Rclex.start_node("watcher", graph_monitor: true)
      :ok = Rclex.start_node("joiner")

      assert_receive {:telemetry, [:rclex, :graph, :node_joined], %{count: 1}, metadata}, 5_000
      assert metadata.node_name == "joiner"
    end

    test "emits node_left when a node leaves the graph" do
      :ok = Rclex.start_node("watcher2", graph_monitor: true)
      :ok = Rclex.start_node("leaver")

      assert_receive {:telemetry, [:rclex, :graph, :node_joined], _, %{node_name: "leaver"}},
                     5_000

      capture_log(fn -> :ok = Rclex.stop_node("leaver") end)

      assert_receive {:telemetry, [:rclex, :graph, :node_left], %{count: 1}, metadata}, 5_000
      assert metadata.node_name == "leaver"
    end

    test "emits one node_joined per node when multiple nodes join" do
      :ok = Rclex.start_node("watcher3", graph_monitor: true)
      :ok = Rclex.start_node("new_a")
      :ok = Rclex.start_node("new_b")

      joined =
        for _ <- 1..2 do
          assert_receive {:telemetry, [:rclex, :graph, :node_joined], %{count: 1}, meta}, 5_000
          meta.node_name
        end

      assert "new_a" in joined
      assert "new_b" in joined
    end
  end

  describe "topic, service, and action telemetry" do
    setup [:attach_all_events]

    test "emits topic_joined when a publisher is added" do
      :ok = Rclex.start_node("topic_watcher", graph_monitor: true)
      :ok = Rclex.start_publisher(StdMsgs.Msg.String, "/gm_chatter", "topic_watcher")

      assert_receive {:telemetry, [:rclex, :graph, :topic_joined], %{count: 1}, metadata}, 5_000
      assert metadata.topic_name == "/gm_chatter"
      assert "std_msgs/msg/String" in metadata.topic_types
    end

    test "emits topic_left when a publisher is removed" do
      :ok = Rclex.start_node("topic_watcher2", graph_monitor: true)
      :ok = Rclex.start_publisher(StdMsgs.Msg.String, "/gm_chatter2", "topic_watcher2")

      assert_receive {:telemetry, [:rclex, :graph, :topic_joined], _,
                      %{topic_name: "/gm_chatter2"}},
                     5_000

      :ok = Rclex.stop_publisher(StdMsgs.Msg.String, "/gm_chatter2", "topic_watcher2")

      assert_receive {:telemetry, [:rclex, :graph, :topic_left], %{count: 1}, metadata}, 5_000
      assert metadata.topic_name == "/gm_chatter2"
    end

    test "emits service_joined when a service server is added" do
      :ok = Rclex.start_node("service_watcher", graph_monitor: true)

      :ok =
        Rclex.start_service(
          fn _req -> nil end,
          StdSrvs.Srv.SetBool,
          "/gm_set_bool",
          "service_watcher"
        )

      assert_receive {:telemetry, [:rclex, :graph, :service_joined], %{count: 1}, metadata}, 5_000
      assert metadata.service_name == "/gm_set_bool"
    end
  end

  describe "on_entity/4" do
    test "fires immediately when node is already in snapshot" do
      me = self()
      handler_id = "oe-immediate-#{inspect(self())}"

      :telemetry.attach(
        handler_id,
        [:rclex, :graph, :node_joined],
        fn _, _, %{node_name: n}, _ -> send(me, {:joined, n}) end,
        nil
      )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      :ok = Rclex.start_node("oe_watcher", graph_monitor: true)
      :ok = Rclex.start_node("oe_target")

      # wait until GraphMonitor has processed the graph_changed and updated its snapshot
      assert_receive {:joined, "oe_target"}, 5_000

      :ok =
        GraphMonitor.on_entity("oe_watcher", {:node, "oe_target", "/"}, fn entity_spec ->
          send(me, {:fired, entity_spec})
        end)

      assert_receive {:fired, {:node, "oe_target", "/"}}
    end

    test "fires when node appears later" do
      me = self()
      :ok = Rclex.start_node("oe_watcher2", graph_monitor: true)

      :ok =
        GraphMonitor.on_entity("oe_watcher2", {:node, "oe_late", "/"}, fn entity_spec ->
          send(me, {:fired, entity_spec})
        end)

      refute_receive {:fired, _}, 200

      :ok = Rclex.start_node("oe_late")
      assert_receive {:fired, {:node, "oe_late", "/"}}, 5_000
    end

    test "fires when topic appears later" do
      me = self()
      :ok = Rclex.start_node("oe_watcher3", graph_monitor: true)

      :ok =
        GraphMonitor.on_entity("oe_watcher3", {:topic, "/oe_topic"}, fn entity_spec ->
          send(me, {:fired, entity_spec})
        end)

      refute_receive {:fired, _}, 200

      :ok = Rclex.start_publisher(StdMsgs.Msg.String, "/oe_topic", "oe_watcher3")
      assert_receive {:fired, {:topic, "/oe_topic"}}, 5_000
    end

    test "fires when service appears later" do
      me = self()
      :ok = Rclex.start_node("oe_watcher4", graph_monitor: true)

      :ok =
        GraphMonitor.on_entity("oe_watcher4", {:service, "/oe_service"}, fn entity_spec ->
          send(me, {:fired, entity_spec})
        end)

      refute_receive {:fired, _}, 200

      :ok =
        Rclex.start_service(fn _req -> nil end, StdSrvs.Srv.SetBool, "/oe_service", "oe_watcher4")

      assert_receive {:fired, {:service, "/oe_service"}}, 5_000
    end
  end

  # shared helper to attach a single telemetry handler for all graph events
  defp attach_all_events(_context) do
    handler_id = "graph-monitor-test-#{inspect(self())}"
    me = self()

    :telemetry.attach_many(
      handler_id,
      [
        [:rclex, :graph, :node_joined],
        [:rclex, :graph, :node_left],
        [:rclex, :graph, :topic_joined],
        [:rclex, :graph, :topic_left],
        [:rclex, :graph, :service_joined],
        [:rclex, :graph, :service_left],
        [:rclex, :graph, :action_joined],
        [:rclex, :graph, :action_left]
      ],
      fn event, measurements, metadata, _config ->
        send(me, {:telemetry, event, measurements, metadata})
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler_id) end)
    :ok
  end
end
