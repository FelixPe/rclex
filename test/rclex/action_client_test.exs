defmodule Rclex.ActionClientTest do
  use ExUnit.Case

  import ExUnit.CaptureLog

  alias Rclex.ActionClient
  alias Rclex.Nif
  alias Rclex.Pkgs.Tf2Msgs.Action

  setup do
    capture_log(fn -> Application.stop(:rclex) end)
    Process.flag(:trap_exit, true)

    name = "name"
    namespace = "/namespace"

    context = Nif.rcl_init!()
    node = Nif.rcl_node_init!(context, ~c"#{name}", ~c"#{namespace}")

    on_exit(fn ->
      :ok = Nif.rcl_node_fini!(node)
      :ok = Nif.rcl_fini!(context)
    end)

    %{context: context, node: node, name: name, namespace: namespace}
  end

  test "start_link/1", %{context: context, node: node, name: name, namespace: namespace} do
    Process.flag(:trap_exit, true)

    assert {:ok, pid} =
             ActionClient.start_link(
               context: context,
               node: node,
               action_type: Action.LookupTransform,
               action_name: "/lookup_transform",
               name: name,
               namespace: namespace
             )

    assert capture_log(fn -> :ok = GenServer.stop(pid, :shutdown) end) =~
             "ActionClient: :shutdown"
  end

  test "start_link/1 failed in init/1 callback", %{
    context: context,
    node: node,
    name: name,
    namespace: namespace
  } do
    Process.flag(:trap_exit, true)

    assert {:error, _} =
             ActionClient.start_link(
               context: context,
               node: node,
               action_type: Action.LookupTransform,
               action_name: "lookup_transform",
               name: name,
               namespace: namespace
             )
  end

  describe "request timeout cleanup" do
    setup %{context: context, node: node, name: name, namespace: namespace} do
      # use very short timeout for testing
      opts = [
        context: context,
        node: node,
        action_type: Action.LookupTransform,
        action_name: "/lookup_transform",
        name: name,
        namespace: namespace,
        options: %{Rclex.ActionClientOptions.default() | request_timeout: 0.01}
      ]

      {:ok, pid} = ActionClient.start_link(opts)

      on_exit(fn ->
        # stop client before tearing down node/context; silence shutdown logs
        _ = capture_log(fn -> GenServer.stop(pid, :shutdown, 5_000) end)
      end)

      %{pid: pid}
    end

    test "goal_requests are removed after timeout", %{pid: pid} do
      goal = struct(Action.LookupTransform.Goal)
      uuid = Rclex.ActionHelpers.gen_uuid()
      fb = fn _ -> :ok end
      ac = fn _uuid, _accepted, _stamp -> :ok end

      _ =
        capture_log(fn ->
          assert {:ok, ^uuid} =
                   ActionClient.send_goal_async(
                     goal,
                     uuid,
                     fb,
                     ac,
                     "/lookup_transform",
                     "name",
                     "/namespace"
                   )

          # wait past the timeout
          Process.sleep(20)
        end)

      state = :sys.get_state(pid)
      assert state.goal_requests == %{}
    end

    test "result_requests cleaned up on timeout", %{pid: pid} do
      uuid = Rclex.ActionHelpers.gen_uuid()
      cb = fn _status, _result -> :ok end

      _ =
        capture_log(fn ->
          assert :ok =
                   ActionClient.get_result_async(
                     uuid,
                     cb,
                     Action.LookupTransform,
                     "/lookup_transform",
                     "name",
                     "/namespace"
                   )

          Process.sleep(20)
        end)

      state = :sys.get_state(pid)
      assert state.result_requests == %{}
    end

    test "cancel_requests cleaned up on timeout", %{pid: pid} do
      uuid = Rclex.ActionHelpers.gen_uuid()
      cb = fn _ret, _goals -> :ok end

      _ =
        capture_log(fn ->
          assert :ok =
                   ActionClient.cancel_goal_async(
                     uuid,
                     cb,
                     Action.LookupTransform,
                     "/lookup_transform",
                     "name",
                     "/namespace"
                   )

          Process.sleep(20)
        end)

      state = :sys.get_state(pid)
      assert state.cancel_requests == %{}
    end
  end
end
