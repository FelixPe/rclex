defmodule Rclex.ParameterEventHandlerTest do
  use ExUnit.Case

  import ExUnit.CaptureLog

  alias Rclex.ParameterEventHandler
  alias Rclex.Pkgs.RclInterfaces.Msg.{Parameter, ParameterEvent, ParameterValue, ParameterType}

  setup do
    :ok = Application.ensure_started(:rclex)
    on_exit(fn -> capture_log(fn -> Application.stop(:rclex) end) end)

    context = Rclex.Context.get()
    server_node = "peh_server"
    client_node = "peh_client"
    namespace = "/test_peh"

    capture_log(fn ->
      Rclex.NodesSupervisor.start_child(context, server_node, namespace)
      Rclex.NodesSupervisor.start_child(context, client_node, namespace)
    end)

    :ok =
      Rclex.declare_parameter(server_node, "an_int",
        type: :integer,
        default_value: 1,
        namespace: namespace
      )

    %{server_node: server_node, client_node: client_node, namespace: namespace}
  end

  describe "start/3 and stop/2" do
    test "subscribes and unsubscribes successfully", ctx do
      capture_log(fn ->
        assert :ok =
                 ParameterEventHandler.start(
                   fn _event -> :ok end,
                   ctx.client_node,
                   namespace: ctx.namespace
                 )

        assert :ok = ParameterEventHandler.stop(ctx.client_node, namespace: ctx.namespace)

        assert {:error, :not_found} =
                 ParameterEventHandler.stop(ctx.client_node, namespace: ctx.namespace)
      end)
    end

    test "default-argument wrappers (no opts) work", _ctx do
      # Use a node that exists at the default "/" namespace.
      context = Rclex.Context.get()

      capture_log(fn ->
        Rclex.NodesSupervisor.start_child(context, "peh_default_args_node", "/")
      end)

      assert {:error, :not_found} = ParameterEventHandler.stop("peh_default_args_node")
    end

    test "calling start twice returns already_started", ctx do
      capture_log(fn ->
        assert :ok =
                 ParameterEventHandler.start(
                   fn _event -> :ok end,
                   ctx.client_node,
                   namespace: ctx.namespace
                 )

        assert {:error, :already_started} =
                 ParameterEventHandler.start(
                   fn _event -> :ok end,
                   ctx.client_node,
                   namespace: ctx.namespace
                 )

        :ok = ParameterEventHandler.stop(ctx.client_node, namespace: ctx.namespace)
      end)
    end

    test "receives parameter event when remote parameter changes", ctx do
      test_pid = self()

      :ok =
        ParameterEventHandler.start(
          fn event -> send(test_pid, {:event, event}) end,
          ctx.client_node,
          namespace: ctx.namespace
        )

      # Trigger a change on the server-side parameter
      Rclex.set_parameter(ctx.server_node, "an_int", 123, namespace: ctx.namespace)

      assert_receive {:event, %ParameterEvent{}}, 5_000

      capture_log(fn ->
        :ok = ParameterEventHandler.stop(ctx.client_node, namespace: ctx.namespace)
      end)
    end
  end

  describe "filtering" do
    # Helper to invoke the matching logic without standing up real subscriptions:
    # we drive the wrapped callback directly by starting and stopping in
    # quick sequence is overkill; instead exercise filters via a private path.
    # The handler's filtering is implemented via `matches?/3` which is
    # internal — exercise it through a fake callback that runs the wrapper.

    setup ctx do
      test_pid = self()

      :ok =
        ParameterEventHandler.start(
          fn event -> send(test_pid, {:event, event}) end,
          ctx.client_node,
          namespace: ctx.namespace,
          node_filter: "#{ctx.namespace}#{ctx.server_node}"
        )

      on_exit(fn ->
        capture_log(fn ->
          ParameterEventHandler.stop(ctx.client_node, namespace: ctx.namespace)
        end)
      end)

      :ok
    end

    test "node_filter forwards events from the matching server", ctx do
      Rclex.set_parameter(ctx.server_node, "an_int", 7, namespace: ctx.namespace)
      assert_receive {:event, %ParameterEvent{node: node}}, 5_000
      assert node == "#{ctx.namespace}#{ctx.server_node}"
    end
  end

  describe "parameter_filter" do
    test "drops events that don't touch any of the named parameters", ctx do
      test_pid = self()

      :ok =
        ParameterEventHandler.start(
          fn event -> send(test_pid, {:event, event}) end,
          ctx.client_node,
          namespace: ctx.namespace,
          parameter_filter: ["nonexistent_param"]
        )

      Rclex.set_parameter(ctx.server_node, "an_int", 13, namespace: ctx.namespace)

      refute_receive {:event, _}, 500

      capture_log(fn ->
        :ok = ParameterEventHandler.stop(ctx.client_node, namespace: ctx.namespace)
      end)
    end

    test "forwards events that touch a listed parameter", ctx do
      test_pid = self()

      :ok =
        ParameterEventHandler.start(
          fn event -> send(test_pid, {:event, event}) end,
          ctx.client_node,
          namespace: ctx.namespace,
          parameter_filter: ["an_int"]
        )

      Rclex.set_parameter(ctx.server_node, "an_int", 21, namespace: ctx.namespace)

      assert_receive {:event, %ParameterEvent{}}, 5_000

      capture_log(fn ->
        :ok = ParameterEventHandler.stop(ctx.client_node, namespace: ctx.namespace)
      end)
    end

    test "empty list is treated as no filter", ctx do
      test_pid = self()

      :ok =
        ParameterEventHandler.start(
          fn event -> send(test_pid, {:event, event}) end,
          ctx.client_node,
          namespace: ctx.namespace,
          parameter_filter: []
        )

      Rclex.set_parameter(ctx.server_node, "an_int", 33, namespace: ctx.namespace)
      assert_receive {:event, %ParameterEvent{}}, 5_000

      capture_log(fn ->
        :ok = ParameterEventHandler.stop(ctx.client_node, namespace: ctx.namespace)
      end)
    end
  end

  describe "non-matching node_filter" do
    test "drops events from a different node", ctx do
      test_pid = self()

      :ok =
        ParameterEventHandler.start(
          fn event -> send(test_pid, {:event, event}) end,
          ctx.client_node,
          namespace: ctx.namespace,
          node_filter: "/some/other_node"
        )

      Rclex.set_parameter(ctx.server_node, "an_int", 99, namespace: ctx.namespace)
      refute_receive {:event, _}, 500

      capture_log(fn ->
        :ok = ParameterEventHandler.stop(ctx.client_node, namespace: ctx.namespace)
      end)
    end
  end

  # The `gen_parameter_value_struct/1` defaults integer to PARAMETER_INTEGER (=2);
  # silence unused-alias warnings.
  _ = ParameterValue
  _ = ParameterType
  _ = Parameter
end
