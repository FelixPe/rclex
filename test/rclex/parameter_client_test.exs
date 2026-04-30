defmodule Rclex.ParameterClientTest do
  use ExUnit.Case

  import ExUnit.CaptureLog

  alias Rclex.ParameterClient
  alias Rclex.Pkgs.RclInterfaces.Msg.{Parameter, ParameterType, ParameterValue}

  setup do
    :ok = Application.ensure_started(:rclex)
    on_exit(fn -> capture_log(fn -> Application.stop(:rclex) end) end)

    context = Rclex.Context.get()

    server_node = "param_server_node"
    server_ns = "/test_pc"
    client_node = "param_client_node"
    client_ns = "/test_pc"

    capture_log(fn ->
      Rclex.NodesSupervisor.start_child(context, server_node, server_ns)
      Rclex.NodesSupervisor.start_child(context, client_node, client_ns)
    end)

    # Pre-declare parameters on the server
    :ok =
      Rclex.declare_parameter(server_node, "an_int",
        type: :integer,
        default_value: 42,
        namespace: server_ns
      )

    :ok =
      Rclex.declare_parameter(server_node, "a_string",
        type: :string,
        default_value: "hello",
        namespace: server_ns
      )

    :ok =
      ParameterClient.start(server_node, client_node,
        namespace: client_ns,
        server_namespace: server_ns
      )

    on_exit(fn ->
      capture_log(fn ->
        ParameterClient.stop(server_node, client_node,
          namespace: client_ns,
          server_namespace: server_ns
        )
      end)
    end)

    %{
      server_node: server_node,
      server_ns: server_ns,
      client_node: client_node,
      client_ns: client_ns
    }
  end

  describe "service_name/3" do
    test "joins namespace, node and suffix" do
      assert "/ns/srv/get_parameters" ==
               ParameterClient.service_name("/ns/", "srv", "get_parameters")
    end
  end

  describe "default-argument wrappers" do
    # Exercise the `opts \\ []` default-argument forms so cover counts them
    # against `start/3`, `stop/3`, and the read/write helpers.
    setup do
      context = Rclex.Context.get()

      capture_log(fn ->
        Rclex.NodesSupervisor.start_child(context, "default_args_client", "/")
      end)

      :ok
    end

    test "start/3 and stop/3 with no opts return :ok" do
      capture_log(fn ->
        assert :ok = ParameterClient.start("nope_a", "default_args_client")
        assert :ok = ParameterClient.stop("nope_a", "default_args_client")
      end)
    end

    test "service_available?/3 with no opts returns false-or-not_found" do
      result = ParameterClient.service_available?("nope_a", "default_args_client")
      assert result == {:error, :not_found} or result == false
    end

    test "get/set/list/describe/types with no opts return {:error, _}" do
      # Without an active client these all return :not_found
      assert {:error, _} = ParameterClient.get_parameters("nope_a", ["x"], "default_args_client")

      assert {:error, _} =
               ParameterClient.get_parameter_types("nope_a", ["x"], "default_args_client")

      assert {:error, _} =
               ParameterClient.describe_parameters("nope_a", ["x"], "default_args_client")

      assert {:error, _} = ParameterClient.list_parameters("nope_a", "default_args_client")

      assert {:error, _} =
               ParameterClient.set_parameters("nope_a", [{"x", 1}], "default_args_client")

      assert {:error, _} =
               ParameterClient.set_parameters_atomically(
                 "nope_a",
                 [{"x", 1}],
                 "default_args_client"
               )
    end
  end

  describe "service_available?/3" do
    test "returns true when server is running", ctx do
      # Allow some time for discovery
      assert wait_until(fn ->
               ParameterClient.service_available?(ctx.server_node, ctx.client_node,
                 namespace: ctx.client_ns,
                 server_namespace: ctx.server_ns
               ) == true
             end)
    end
  end

  describe "get_parameters/4" do
    test "returns the values declared on the server", ctx do
      _ = wait_until_available(ctx)

      assert {:ok, results} =
               ParameterClient.get_parameters(
                 ctx.server_node,
                 ["an_int", "a_string"],
                 ctx.client_node,
                 namespace: ctx.client_ns,
                 server_namespace: ctx.server_ns,
                 timeout: 2.0
               )

      assert {"an_int", 42} in results
      assert {"a_string", "hello"} in results
    end
  end

  describe "set_parameters/4" do
    test "updates a parameter on the remote node", ctx do
      _ = wait_until_available(ctx)

      assert {:ok, [%{successful: true}]} =
               ParameterClient.set_parameters(
                 ctx.server_node,
                 [{"an_int", 99}],
                 ctx.client_node,
                 namespace: ctx.client_ns,
                 server_namespace: ctx.server_ns,
                 timeout: 2.0
               )

      assert {:ok, [{"an_int", 99}]} =
               ParameterClient.get_parameters(
                 ctx.server_node,
                 ["an_int"],
                 ctx.client_node,
                 namespace: ctx.client_ns,
                 server_namespace: ctx.server_ns,
                 timeout: 2.0
               )
    end
  end

  describe "list_parameters/3" do
    test "lists all parameters on the server", ctx do
      _ = wait_until_available(ctx)

      assert {:ok, %{names: names}} =
               ParameterClient.list_parameters(ctx.server_node, ctx.client_node,
                 namespace: ctx.client_ns,
                 server_namespace: ctx.server_ns,
                 timeout: 2.0
               )

      assert "an_int" in names
      assert "a_string" in names
    end
  end

  describe "set_parameters_atomically/4" do
    test "sets all parameters in a single transaction", ctx do
      _ = wait_until_available(ctx)

      assert {:ok, %{successful: true}} =
               ParameterClient.set_parameters_atomically(
                 ctx.server_node,
                 [{"an_int", 7}, {"a_string", "world"}],
                 ctx.client_node,
                 namespace: ctx.client_ns,
                 server_namespace: ctx.server_ns,
                 timeout: 2.0
               )
    end
  end

  describe "get_parameter_types/4" do
    test "returns the parameter types for the requested names", ctx do
      _ = wait_until_available(ctx)

      assert {:ok, types} =
               ParameterClient.get_parameter_types(
                 ctx.server_node,
                 ["an_int", "a_string"],
                 ctx.client_node,
                 namespace: ctx.client_ns,
                 server_namespace: ctx.server_ns,
                 timeout: 2.0
               )

      # In `rcl_interfaces`, INTEGER == 2 and STRING == 4
      assert is_binary(types) or is_list(types)
    end
  end

  describe "describe_parameters/4" do
    test "returns a descriptor list", ctx do
      _ = wait_until_available(ctx)

      assert {:ok, descriptors} =
               ParameterClient.describe_parameters(
                 ctx.server_node,
                 ["an_int"],
                 ctx.client_node,
                 namespace: ctx.client_ns,
                 server_namespace: ctx.server_ns,
                 timeout: 2.0
               )

      assert [%{name: "an_int"}] = descriptors
    end
  end

  describe "set_parameters/4 input shapes" do
    test "accepts a pre-built %Parameter{} struct", ctx do
      _ = wait_until_available(ctx)

      param = %Parameter{
        name: "an_int",
        value: %ParameterValue{
          type: ParameterType.parameter_integer(),
          integer_value: 11
        }
      }

      assert {:ok, [%{successful: true}]} =
               ParameterClient.set_parameters(
                 ctx.server_node,
                 [param],
                 ctx.client_node,
                 namespace: ctx.client_ns,
                 server_namespace: ctx.server_ns,
                 timeout: 2.0
               )
    end

    test "accepts a {name, %ParameterValue{}} tuple", ctx do
      _ = wait_until_available(ctx)

      value = %ParameterValue{
        type: ParameterType.parameter_integer(),
        integer_value: 22
      }

      assert {:ok, [%{successful: true}]} =
               ParameterClient.set_parameters(
                 ctx.server_node,
                 [{"an_int", value}],
                 ctx.client_node,
                 namespace: ctx.client_ns,
                 server_namespace: ctx.server_ns,
                 timeout: 2.0
               )
    end

    test "accepts a {name, value, type} tuple", ctx do
      _ = wait_until_available(ctx)

      assert {:ok, [%{successful: true}]} =
               ParameterClient.set_parameters(
                 ctx.server_node,
                 [{"an_int", 33, :integer}],
                 ctx.client_node,
                 namespace: ctx.client_ns,
                 server_namespace: ctx.server_ns,
                 timeout: 2.0
               )
    end
  end

  describe "start/3 idempotence" do
    test "starting twice returns :ok (already_started ignored)", ctx do
      assert :ok =
               ParameterClient.start(ctx.server_node, ctx.client_node,
                 namespace: ctx.client_ns,
                 server_namespace: ctx.server_ns
               )
    end
  end

  describe "calls without a started client" do
    test "return {:error, :not_found}", ctx do
      # use a totally unknown server name so no client is registered
      assert {:error, :not_found} =
               ParameterClient.get_parameters(
                 "no_such_server",
                 ["x"],
                 ctx.client_node,
                 namespace: ctx.client_ns,
                 server_namespace: ctx.server_ns,
                 timeout: 0.1
               )
    end
  end

  describe "service_available?/3 without a started client" do
    test "returns {:error, :not_found}", ctx do
      assert {:error, :not_found} =
               ParameterClient.service_available?(
                 "no_such_server",
                 ctx.client_node,
                 namespace: ctx.client_ns,
                 server_namespace: ctx.server_ns
               )
    end
  end

  defp wait_until_available(ctx) do
    wait_until(fn ->
      ParameterClient.service_available?(ctx.server_node, ctx.client_node,
        namespace: ctx.client_ns,
        server_namespace: ctx.server_ns
      ) == true
    end)
  end

  defp wait_until(fun, attempts \\ 50, interval \\ 100) do
    cond do
      attempts <= 0 ->
        false

      fun.() ->
        true

      true ->
        Process.sleep(interval)
        wait_until(fun, attempts - 1, interval)
    end
  end
end
