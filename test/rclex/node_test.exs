defmodule Rclex.NodeTest do
  use ExUnit.Case

  import ExUnit.CaptureLog

  alias Rclex.Node
  alias Rclex.Nif

  setup do
    capture_log(fn -> Application.stop(:rclex) end)

    context = Nif.rcl_init!()
    on_exit(fn -> :ok = Nif.rcl_fini!(context) end)

    %{context: context}
  end

  test "start_link/1", %{context: context} do
    Process.flag(:trap_exit, true)

    assert {:ok, pid} = Node.start_link(context: context, name: "name", namespace: "/namespace")

    assert capture_log(fn -> :ok = GenServer.stop(pid, :shutdown) end) =~
             "Node: :shutdown"
  end

  test "start_link/1 failed in init/1 callback", %{context: context} do
    Process.flag(:trap_exit, true)

    assert {:error, _} =
             Node.start_link(context: context, name: "name", namespace: "no_leading_slash")
  end

  test "supervised node death finalizes the original native handle", %{context: context} do
    supervisor =
      start_supervised!(
        {Rclex.NodeSupervisor,
         context: context,
         name: "killed_node",
         namespace: "/",
         start_parameter_server: false,
         type_description_service: false}
      )

    node = GenServer.whereis(Node.name("killed_node"))
    handle = :sys.get_state(node).node
    monitor = Process.monitor(node)

    try do
      Process.exit(node, :kill)
      assert_receive {:DOWN, ^monitor, :process, ^node, :killed}
      assert :ok = Supervisor.stop(supervisor)

      assert_raise ErlangError, fn -> Nif.rcl_node_get_graph_guard_condition!(handle) end
    after
      try do
        Nif.rcl_node_fini!(handle)
      rescue
        ErlangError -> :ok
      end
    end
  end

  test "one_for_all restart replaces the native owner and graph waiter", %{context: context} do
    caller = self()

    supervisor =
      start_supervised!(
        {Rclex.NodeSupervisor,
         context: context,
         name: "restarted_node",
         namespace: "/",
         graph_change_callback: fn -> send(caller, {:graph_event, self()}) end,
         start_parameter_server: false,
         type_description_service: false}
      )

    owner = GenServer.whereis(Rclex.NodeResourceOwner.name("restarted_node", "/"))
    node = GenServer.whereis(Node.name("restarted_node"))
    %{node: handle, wait_thread: wait_thread} = :sys.get_state(owner)
    assert is_reference(wait_thread)
    assert_receive {:graph_event, ^node}, 2_000
    monitor = Process.monitor(owner)

    Process.exit(node, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^owner, :shutdown}, 2_000

    children = Supervisor.which_children(supervisor)
    {Node, replacement, _, _} = List.keyfind(children, Node, 0)

    {Rclex.NodeResourceOwner, replacement_owner, _, _} =
      List.keyfind(children, Rclex.NodeResourceOwner, 0)

    assert replacement != node
    assert replacement_owner != owner
    assert :sys.get_state(replacement_owner).node != handle
    assert_receive {:graph_event, ^replacement}, 2_000
    assert :ok = Supervisor.stop(supervisor)
    assert_raise ErlangError, fn -> Nif.rcl_node_get_graph_guard_condition!(handle) end
  end

  test "orderly supervised shutdown finalizes a borrowed native handle", %{context: context} do
    supervisor =
      start_supervised!(
        {Rclex.NodeSupervisor,
         context: context,
         name: "stopped_node",
         namespace: "/",
         start_parameter_server: false,
         type_description_service: false}
      )

    node = GenServer.whereis(Node.name("stopped_node"))
    handle = :sys.get_state(node).node
    assert :ok = Supervisor.stop(supervisor)
    assert_raise ErlangError, fn -> Nif.rcl_node_get_graph_guard_condition!(handle) end
  end

  test "graph wait errors leave cleanup to ordered supervisor teardown", %{context: context} do
    supervisor =
      start_supervised!(
        {Rclex.NodeSupervisor,
         context: context,
         name: "graph_error_node",
         namespace: "/",
         graph_change_callback: fn -> :ok end,
         start_parameter_server: false,
         type_description_service: false}
      )

    owner = GenServer.whereis(Rclex.NodeResourceOwner.name("graph_error_node", "/"))
    node = GenServer.whereis(Node.name("graph_error_node"))
    entities = GenServer.whereis(Rclex.EntitiesSupervisor.name("graph_error_node"))
    handle = :sys.get_state(node).node
    node_monitor = Process.monitor(node)
    owner_monitor = Process.monitor(owner)
    caller = self()

    {:ok, barrier} =
      DynamicSupervisor.start_child(entities, %{
        id: :shutdown_barrier,
        restart: :temporary,
        shutdown: :infinity,
        start:
          {Task, :start_link,
           [
             fn ->
               Process.flag(:trap_exit, true)
               send(caller, :barrier_ready)

               receive do
                 {:EXIT, _parent, :shutdown} ->
                   send(caller, :entity_stopping)

                   receive do
                     :finish_shutdown -> :ok
                   end
               end
             end
           ]}
      })

    assert_receive :barrier_ready

    try do
      send(owner, {:error, :new_graph_event})

      assert_receive {:DOWN, ^node_monitor, :process, ^node,
                      {:graph_waitset_error, :new_graph_event}},
                     2_000

      assert_receive :entity_stopping, 2_000
      assert Process.alive?(owner)
      assert is_reference(Nif.rcl_node_get_graph_guard_condition!(handle))
    after
      send(barrier, :finish_shutdown)
    end

    assert_receive {:DOWN, ^owner_monitor, :process, ^owner, :shutdown}, 2_000
    assert :ok = Supervisor.stop(supervisor)
  end

  test "context finalization survives node death and partial supervisor startup" do
    probe = """
    Logger.configure(level: :critical)
    {:ok, _} = Application.ensure_all_started(:rclex)
    :ok = Rclex.start_node("context_cleanup_probe", graph_change_callback: fn -> :ok end)
    node = GenServer.whereis(Rclex.Node.name("context_cleanup_probe"))
    monitor = Process.monitor(node)
    Process.exit(node, :kill)
    receive do
      {:DOWN, ^monitor, :process, ^node, :killed} -> :ok
    end
    :ok = Rclex.stop_node("context_cleanup_probe")
    {:ok, blocker} =
      Rclex.EntitiesSupervisor.start_link(name: "startup_failure_probe", namespace: "/")
    {:error, _} = Rclex.start_node("startup_failure_probe")
    :ok = Supervisor.stop(blocker)
    :ok = Application.stop(:rclex)
    IO.puts("native context finalized")
    """

    paths = Enum.flat_map(:code.get_path(), fn path -> ["-pa", List.to_string(path)] end)

    {output, status} =
      System.cmd(System.find_executable("elixir"), ["--erl", "+S 2:2"] ++ paths ++ ["-e", probe],
        stderr_to_stdout: true
      )

    assert status == 0, output
    assert output =~ "native context finalized"
    refute output =~ "active nodes"
    refute output =~ "memory may be leaked"
    refute output =~ "Not all nodes were finished"
  end
end
