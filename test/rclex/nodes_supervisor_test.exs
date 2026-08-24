defmodule Rclex.NodesSupervisorTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Rclex.NodesSupervisor

  setup do
    :ok = Application.ensure_started(:rclex)

    on_exit(fn ->
      capture_log(fn ->
        _ = NodesSupervisor.terminate_child("nodes_supervisor_default_child")
      end)
    end)

    :ok
  end

  test "name/0 returns the registered supervisor name" do
    assert NodesSupervisor.name() == Rclex.NodesSupervisor
  end

  test "terminate_child/2 returns not_found for an unknown node" do
    assert NodesSupervisor.terminate_child("missing_node", "/missing_namespace") ==
             {:error, :not_found}
  end

  test "start_child/2 starts a node using defaults and terminate_child/1 stops it" do
    assert {:ok, _pid} =
             NodesSupervisor.start_child(Rclex.Context.get(), "nodes_supervisor_default_child")

    assert %{name: "nodes_supervisor_default_child", namespace: "/"} in NodesSupervisor.get_local_nodes()

    assert :ok = NodesSupervisor.terminate_child("nodes_supervisor_default_child")

    assert NodesSupervisor.terminate_child("nodes_supervisor_default_child") ==
             {:error, :not_found}
  end
end
