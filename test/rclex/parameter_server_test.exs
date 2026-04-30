defmodule Rclex.ParameterServerTest do
  use ExUnit.Case

  import ExUnit.CaptureLog

  alias Rclex.ParameterServer
  alias Rclex.ParameterHelpers

  # Service types for testing
  alias Rclex.Pkgs.RclInterfaces.Srv.GetParameters
  alias Rclex.Pkgs.RclInterfaces.Srv.SetParameters
  alias Rclex.Pkgs.RclInterfaces.Srv.SetParametersAtomically
  alias Rclex.Pkgs.RclInterfaces.Srv.ListParameters
  alias Rclex.Pkgs.RclInterfaces.Srv.DescribeParameters
  alias Rclex.Pkgs.RclInterfaces.Srv.GetParameterTypes

  # Message types
  alias Rclex.Pkgs.RclInterfaces.Msg.{
    ParameterType,
    ParameterEvent,
    ParameterEventDescriptors
  }

  setup do
    # Initialize the ROS 2 context and node supervisor
    :ok = Application.ensure_started(:rclex)
    on_exit(fn -> capture_log(fn -> Application.stop(:rclex) end) end)

    context = Rclex.Context.get()
    node_name = "test_param_node"
    namespace = "/test_ns"

    capture_log(fn -> Rclex.NodesSupervisor.start_child(context, node_name, namespace) end)

    %{
      context: context,
      node_name: node_name,
      namespace: namespace
    }
  end

  describe "start_link/1" do
    test "starts parameter server with proper name", %{node_name: node_name, namespace: namespace} do
      # Parameter server should be started automatically by Node
      server_pid = GenServer.whereis(ParameterServer.name(node_name, namespace))
      assert is_pid(server_pid)
      assert Process.alive?(server_pid)
    end

    test "creates global process name", %{node_name: node_name, namespace: namespace} do
      expected_name = {:global, {:parameter_server, node_name, namespace}}
      assert ParameterServer.name(node_name, namespace) == expected_name
    end
  end

  describe "parameter declaration and management" do
    test "declare_parameter creates new parameter", %{node_name: node_name, namespace: namespace} do
      # Declare a parameter
      assert :ok =
               ParameterServer.declare_parameter(node_name, namespace, "test_param",
                 type: :integer,
                 default_value: 42
               )

      # Verify parameter exists
      assert {:ok,
              %Rclex.Pkgs.RclInterfaces.Msg.ParameterValue{
                type: 2,
                bool_value: false,
                integer_value: 42,
                double_value: +0.0,
                string_value: "",
                integer_array_value: [],
                byte_array_value: [],
                bool_array_value: [],
                double_array_value: [],
                string_array_value: []
              }} = ParameterServer.get_parameter(node_name, namespace, "test_param")
    end

    test "declare_parameter with descriptor", %{node_name: node_name, namespace: namespace} do
      assert :ok =
               ParameterServer.declare_parameter(node_name, namespace, "test_param",
                 type: :integer,
                 default_value: 100,
                 description: "A test parameter",
                 read_only: true,
                 additional_constraints: "Must be positive"
               )

      # Verify parameter and descriptor
      assert {:ok,
              %Rclex.Pkgs.RclInterfaces.Msg.ParameterValue{
                type: 2,
                bool_value: false,
                integer_value: 100,
                double_value: +0.0,
                string_value: "",
                integer_array_value: [],
                byte_array_value: [],
                bool_array_value: [],
                double_array_value: [],
                string_array_value: []
              }} = ParameterServer.get_parameter(node_name, namespace, "test_param")

      [param_desc] = ParameterServer.describe_parameters(node_name, namespace, ["test_param"])
      assert param_desc.name == "test_param"
      assert param_desc.description == "A test parameter"
      assert param_desc.read_only == true
      assert param_desc.additional_constraints == "Must be positive"
    end

    test "declare_parameter fails when already declared", %{
      node_name: node_name,
      namespace: namespace
    } do
      assert :ok =
               ParameterServer.declare_parameter(node_name, namespace, "duplicate_param",
                 default_value: 1
               )

      assert {:error, :already_declared} =
               ParameterServer.declare_parameter(node_name, namespace, "duplicate_param",
                 default_value: 2
               )
    end

    test "get_parameter fails for undeclared parameter", %{
      node_name: node_name,
      namespace: namespace
    } do
      assert {:error, :not_declared} =
               ParameterServer.get_parameter(node_name, namespace, "undeclared_param")
    end

    test "set_parameter updates existing parameter", %{node_name: node_name, namespace: namespace} do
      # Declare and set parameter
      assert :ok =
               ParameterServer.declare_parameter(node_name, namespace, "update_param",
                 default_value: "initial"
               )

      assert :ok =
               ParameterServer.set_parameter(
                 node_name,
                 namespace,
                 "update_param",
                 "updated"
               )

      # Verify update
      assert {:ok,
              %Rclex.Pkgs.RclInterfaces.Msg.ParameterValue{
                type: 4,
                bool_value: false,
                integer_value: 0,
                double_value: +0.0,
                string_value: "updated",
                integer_array_value: [],
                byte_array_value: [],
                bool_array_value: [],
                double_array_value: [],
                string_array_value: []
              }} = ParameterServer.get_parameter(node_name, namespace, "update_param")
    end

    test "set_parameter fails for undeclared parameter", %{
      node_name: node_name,
      namespace: namespace
    } do
      assert {:error, :not_declared} =
               ParameterServer.set_parameter(node_name, namespace, "undeclared", 42)
    end

    test "set_parameters atomically succeeds when all parameters exist", %{
      node_name: node_name,
      namespace: namespace
    } do
      # Declare parameters
      assert :ok =
               ParameterServer.declare_parameter(node_name, namespace, "param1",
                 type: :integer,
                 default_value: 1
               )

      assert :ok =
               ParameterServer.declare_parameter(node_name, namespace, "param2",
                 type: :integer,
                 default_value: 2
               )

      # Set multiple parameters
      assert :ok =
               ParameterServer.set_parameters(
                 node_name,
                 namespace,
                 [
                   {"param1", Rclex.ParameterHelpers.gen_parameter_value_struct(10, :integer)},
                   {"param2", Rclex.ParameterHelpers.gen_parameter_value_struct(20, :integer)}
                 ],
                 false,
                 true
               )

      # Verify updates
      assert {:ok,
              %Rclex.Pkgs.RclInterfaces.Msg.ParameterValue{
                type: 2,
                bool_value: false,
                integer_value: 10,
                double_value: +0.0,
                string_value: "",
                integer_array_value: [],
                byte_array_value: [],
                bool_array_value: [],
                double_array_value: [],
                string_array_value: []
              }} = ParameterServer.get_parameter(node_name, namespace, "param1")

      assert {:ok,
              %Rclex.Pkgs.RclInterfaces.Msg.ParameterValue{
                type: 2,
                bool_value: false,
                integer_value: 20,
                double_value: +0.0,
                string_value: "",
                integer_array_value: [],
                byte_array_value: [],
                bool_array_value: [],
                double_array_value: [],
                string_array_value: []
              }} = ParameterServer.get_parameter(node_name, namespace, "param2")
    end

    test "set_parameters atomically publishes only touched parameters in changed event", %{
      node_name: node_name,
      namespace: namespace
    } do
      assert :ok =
               ParameterServer.declare_parameter(node_name, namespace, "param1",
                 type: :integer,
                 default_value: 1
               )

      assert :ok =
               ParameterServer.declare_parameter(node_name, namespace, "param2",
                 type: :integer,
                 default_value: 2
               )

      me = self()
      topic = "/parameter_events"

      assert :ok =
               Rclex.start_subscription(&send(me, &1), ParameterEvent, topic, node_name,
                 namespace: namespace
               )

      on_exit(fn ->
        capture_log(fn ->
          _ = Rclex.stop_subscription(ParameterEvent, topic, node_name, namespace: namespace)
        end)
      end)

      assert :ok =
               ParameterServer.set_parameters(
                 node_name,
                 namespace,
                 [{"param1", Rclex.ParameterHelpers.gen_parameter_value_struct(10, :integer)}],
                 false,
                 true
               )

      assert_receive %ParameterEvent{} = event, 2_000

      changed_names = Enum.map(event.changed_parameters, & &1.name)
      new_names = Enum.map(event.new_parameters, & &1.name)
      deleted_names = Enum.map(event.deleted_parameters, & &1.name)

      assert changed_names == ["param1"]
      assert new_names == []
      assert deleted_names == []
    end

    test "set_parameters non-atomically publishes only touched parameters in changed event", %{
      node_name: node_name,
      namespace: namespace
    } do
      assert :ok =
               ParameterServer.declare_parameter(node_name, namespace, "param1",
                 type: :integer,
                 default_value: 1
               )

      assert :ok =
               ParameterServer.declare_parameter(node_name, namespace, "param2",
                 type: :integer,
                 default_value: 2
               )

      me = self()
      topic = "/parameter_events"

      assert :ok =
               Rclex.start_subscription(&send(me, &1), ParameterEvent, topic, node_name,
                 namespace: namespace
               )

      on_exit(fn ->
        capture_log(fn ->
          _ = Rclex.stop_subscription(ParameterEvent, topic, node_name, namespace: namespace)
        end)
      end)

      assert [result] =
               ParameterServer.set_parameters(
                 node_name,
                 namespace,
                 [{"param1", Rclex.ParameterHelpers.gen_parameter_value_struct(10, :integer)}],
                 false,
                 false
               )

      assert result.successful
      assert_receive %ParameterEvent{} = event, 2_000

      changed_names = Enum.map(event.changed_parameters, & &1.name)
      new_names = Enum.map(event.new_parameters, & &1.name)
      deleted_names = Enum.map(event.deleted_parameters, & &1.name)

      assert changed_names == ["param1"]
      assert new_names == []
      assert deleted_names == []
    end

    test "set_parameters non-atomically publishes descriptors on /parameter_event_descriptors", %{
      node_name: node_name,
      namespace: namespace
    } do
      assert :ok =
               ParameterServer.declare_parameter(node_name, namespace, "param1",
                 type: :integer,
                 default_value: 1
               )

      assert :ok =
               ParameterServer.declare_parameter(node_name, namespace, "param2",
                 type: :integer,
                 default_value: 2
               )

      me = self()
      topic = "/parameter_event_descriptors"

      assert :ok =
               Rclex.start_subscription(
                 &send(me, &1),
                 ParameterEventDescriptors,
                 topic,
                 node_name,
                 namespace: namespace
               )

      on_exit(fn ->
        capture_log(fn ->
          _ =
            Rclex.stop_subscription(ParameterEventDescriptors, topic, node_name,
              namespace: namespace
            )
        end)
      end)

      assert [result] =
               ParameterServer.set_parameters(
                 node_name,
                 namespace,
                 [{"param1", Rclex.ParameterHelpers.gen_parameter_value_struct(10, :integer)}],
                 false,
                 false
               )

      assert result.successful
      assert_receive %ParameterEventDescriptors{} = event, 2_000

      changed_names = Enum.map(event.changed_parameters, & &1.name)
      new_names = Enum.map(event.new_parameters, & &1.name)
      deleted_names = Enum.map(event.deleted_parameters, & &1.name)

      assert changed_names == ["param1"]
      assert new_names == []
      assert deleted_names == []
    end

    test "set_parameters fails when any parameter is undeclared", %{
      node_name: node_name,
      namespace: namespace
    } do
      assert :ok =
               ParameterServer.declare_parameter(node_name, namespace, "param1",
                 type: :integer,
                 default_value: 1
               )

      # Attempt to set declared and undeclared parameters
      result =
        ParameterServer.set_parameters(
          node_name,
          namespace,
          [{"param1", 10}, {"undeclared", 20}],
          true
        )

      assert {:error, {:undeclared_parameters, ["undeclared"]}} = result

      # Verify first parameter was not changed
      assert {:ok,
              %Rclex.Pkgs.RclInterfaces.Msg.ParameterValue{
                type: 2,
                bool_value: false,
                integer_value: 1,
                double_value: +0.0,
                string_value: "",
                integer_array_value: [],
                byte_array_value: [],
                bool_array_value: [],
                double_array_value: [],
                string_array_value: []
              }} = ParameterServer.get_parameter(node_name, namespace, "param1")
    end

    test "list_parameters returns all declared parameter names", %{
      node_name: node_name,
      namespace: namespace
    } do
      # Initially empty
      assert [] = ParameterServer.list_parameters(node_name, namespace)

      # Declare some parameters
      assert :ok =
               ParameterServer.declare_parameter(node_name, namespace, "param1", default_value: 1)

      assert :ok =
               ParameterServer.declare_parameter(node_name, namespace, "param2",
                 default_value: "hello"
               )

      assert :ok =
               ParameterServer.declare_parameter(node_name, namespace, "param3",
                 default_value: true
               )

      # Check list
      param_names = ParameterServer.list_parameters(node_name, namespace)
      assert length(param_names) == 3
      assert "param1" in param_names
      assert "param2" in param_names
      assert "param3" in param_names
    end

    test "describe_parameters returns descriptors for specified parameters", %{
      node_name: node_name,
      namespace: namespace
    } do
      # Declare parameters with different types
      assert :ok =
               ParameterServer.declare_parameter(node_name, namespace, "int_param",
                 type: :integer,
                 default_value: 42
               )

      assert :ok =
               ParameterServer.declare_parameter(node_name, namespace, "string_param",
                 type: :string,
                 default_value: "hello"
               )

      # Get descriptors for specific parameters
      descriptors =
        ParameterServer.describe_parameters(node_name, namespace, ["int_param", "string_param"])

      assert length(descriptors) == 2

      # Find descriptors by name
      int_desc = Enum.find(descriptors, &(&1.name == "int_param"))
      string_desc = Enum.find(descriptors, &(&1.name == "string_param"))

      assert int_desc != nil
      assert string_desc != nil
      assert int_desc.type == ParameterType.parameter_integer()
      assert string_desc.type == ParameterType.parameter_string()
    end

    test "describe_parameters returns all descriptors when no names specified", %{
      node_name: node_name,
      namespace: namespace
    } do
      # Declare parameters
      assert :ok =
               ParameterServer.declare_parameter(node_name, namespace, "param1",
                 type: :integer,
                 default_value: 1
               )

      assert :ok =
               ParameterServer.declare_parameter(node_name, namespace, "param2",
                 type: :float,
                 default_value: 2.5
               )

      # Get all descriptors
      descriptors = ParameterServer.describe_parameters(node_name, namespace, [])
      assert length(descriptors) == 2

      param_names = Enum.map(descriptors, & &1.name)
      assert "param1" in param_names
      assert "param2" in param_names
    end

    test "get_parameter_types returns correct types", %{
      node_name: node_name,
      namespace: namespace
    } do
      # Declare parameters of different types
      assert :ok =
               ParameterServer.declare_parameter(node_name, namespace, "bool_param",
                 type: :boolean,
                 default_value: true
               )

      assert :ok =
               ParameterServer.declare_parameter(node_name, namespace, "int_param",
                 type: :integer,
                 default_value: 42
               )

      assert :ok =
               ParameterServer.declare_parameter(node_name, namespace, "double_param",
                 type: :float,
                 default_value: 3.14
               )

      assert :ok =
               ParameterServer.declare_parameter(node_name, namespace, "string_param",
                 type: :string,
                 default_value: "hello"
               )

      assert :ok =
               ParameterServer.declare_parameter(node_name, namespace, "byte_array_param",
                 type: :byte_array,
                 default_value: [
                   1,
                   2,
                   3
                 ]
               )

      assert :ok =
               ParameterServer.declare_parameter(node_name, namespace, "int_array_param",
                 type: :integer_array,
                 default_value: [
                   100,
                   200,
                   300
                 ]
               )

      # Get parameter types
      types =
        ParameterServer.get_parameter_types(node_name, namespace, [
          "bool_param",
          "int_param",
          "double_param",
          "string_param",
          "byte_array_param",
          "int_array_param",
          "undeclared"
        ])

      assert types == [
               :boolean,
               :integer,
               :float,
               :string,
               :byte_array,
               :integer_array,
               :not_declared
             ]
    end
  end

  describe "parameter callbacks" do
    test "parameter callbacks are notified on parameter changes", %{
      node_name: node_name,
      namespace: namespace
    } do
      test_pid = self()

      # Add callback
      callback = fn name, new_value, old_value ->
        send(test_pid, {:param_changed, name, new_value, old_value})
      end

      assert :ok =
               ParameterServer.add_post_set_parameters_callback(node_name, namespace, callback)

      # Declare and set parameter
      assert :ok =
               ParameterServer.declare_parameter(node_name, namespace, "watched_param",
                 type: :string,
                 default_value: "initial"
               )

      assert :ok =
               ParameterServer.set_parameter(
                 node_name,
                 namespace,
                 "watched_param",
                 "updated"
               )

      # Wait for callback notification
      assert_receive {:param_changed, "watched_param", _new_value, nil}, 1000
      assert_receive {:param_changed, "watched_param", new_value, old_value}, 1000

      assert new_value == "updated"
      assert old_value == "initial"
    end

    test "remove_post_set_parameters_callback stops notifications", %{
      node_name: node_name,
      namespace: namespace
    } do
      test_pid = self()

      callback = fn name, _new_value, _old_value ->
        send(test_pid, {:param_changed, name})
      end

      # Add and then remove callback
      assert :ok =
               ParameterServer.add_post_set_parameters_callback(node_name, namespace, callback)

      assert :ok =
               ParameterServer.remove_post_set_parameters_callback(node_name, namespace, callback)

      # Declare and set parameter
      assert :ok =
               ParameterServer.declare_parameter(node_name, namespace, "unwatched_param",
                 default_value: "initial"
               )

      assert :ok =
               ParameterServer.set_parameter(
                 node_name,
                 namespace,
                 "unwatched_param",
                 "updated"
               )

      # Should not receive callback
      refute_receive {:param_changed, "unwatched_param"}, 100
    end

    test "pre-set callback can rewrite parameter values before apply", %{
      node_name: node_name,
      namespace: namespace
    } do
      assert :ok =
               ParameterServer.declare_parameter(node_name, namespace, "pre_param",
                 type: :integer,
                 default_value: 1
               )

      pre_callback = fn parameters ->
        Enum.map(parameters, fn
          {"pre_param", _value} ->
            {"pre_param", Rclex.ParameterHelpers.gen_parameter_value_struct(99, :integer)}

          other ->
            other
        end)
      end

      assert :ok =
               ParameterServer.add_pre_set_parameters_callback(node_name, namespace, pre_callback)

      assert :ok =
               ParameterServer.set_parameter(
                 node_name,
                 namespace,
                 "pre_param",
                 10
               )

      assert {:ok,
              %Rclex.Pkgs.RclInterfaces.Msg.ParameterValue{
                integer_value: 99
              }} = ParameterServer.get_parameter(node_name, namespace, "pre_param")
    end

    test "on-set callback can reject updates", %{node_name: node_name, namespace: namespace} do
      assert :ok =
               ParameterServer.declare_parameter(node_name, namespace, "guarded_param",
                 type: :integer,
                 default_value: 5
               )

      on_callback = fn _parameters -> {:error, "blocked by on-set callback"} end

      assert :ok =
               ParameterServer.add_on_set_parameters_callback(node_name, namespace, on_callback)

      assert {:error, "blocked by on-set callback"} =
               ParameterServer.set_parameter(
                 node_name,
                 namespace,
                 "guarded_param",
                 50
               )

      assert {:ok,
              %Rclex.Pkgs.RclInterfaces.Msg.ParameterValue{
                integer_value: 5
              }} = ParameterServer.get_parameter(node_name, namespace, "guarded_param")
    end

    test "pre, on, and post callbacks execute in phase order", %{
      node_name: node_name,
      namespace: namespace
    } do
      test_pid = self()

      assert :ok =
               ParameterServer.declare_parameter(node_name, namespace, "ordered_param",
                 type: :integer,
                 default_value: 1
               )

      pre_callback = fn parameters ->
        send(test_pid, :pre_phase)
        parameters
      end

      on_callback = fn _parameters ->
        send(test_pid, :on_phase)
        :ok
      end

      post_callback = fn name, _new_value, _old_value ->
        send(test_pid, {:post_phase, name})
      end

      assert :ok =
               ParameterServer.add_pre_set_parameters_callback(node_name, namespace, pre_callback)

      assert :ok =
               ParameterServer.add_on_set_parameters_callback(node_name, namespace, on_callback)

      assert :ok =
               ParameterServer.add_post_set_parameters_callback(
                 node_name,
                 namespace,
                 post_callback
               )

      assert :ok = ParameterServer.set_parameter(node_name, namespace, "ordered_param", 2)

      assert_receive :pre_phase, 1_000
      assert_receive :on_phase, 1_000
      assert_receive {:post_phase, "ordered_param"}, 1_000
    end

    test "post-set callbacks execute in registration order (FIFO)", %{
      node_name: node_name,
      namespace: namespace
    } do
      test_pid = self()

      assert :ok =
               ParameterServer.declare_parameter(node_name, namespace, "fifo_param",
                 type: :integer,
                 default_value: 1
               )

      first_callback = fn _name, _new_value, _old_value ->
        send(test_pid, :first)
      end

      second_callback = fn _name, _new_value, _old_value ->
        send(test_pid, :second)
      end

      assert :ok =
               ParameterServer.add_post_set_parameters_callback(
                 node_name,
                 namespace,
                 first_callback
               )

      assert :ok =
               ParameterServer.add_post_set_parameters_callback(
                 node_name,
                 namespace,
                 second_callback
               )

      assert :ok = ParameterServer.set_parameter(node_name, namespace, "fifo_param", 2)

      assert_receive :first, 1_000
      assert_receive :second, 1_000
    end
  end

  describe "parameter value types" do
    test "supports boolean parameters", %{node_name: node_name, namespace: namespace} do
      assert :ok =
               ParameterServer.declare_parameter(node_name, namespace, "bool_param",
                 type: :boolean,
                 default_value: true
               )

      assert {:ok,
              %Rclex.Pkgs.RclInterfaces.Msg.ParameterValue{
                type: 1,
                bool_value: true,
                integer_value: 0,
                double_value: +0.0,
                string_value: "",
                integer_array_value: [],
                byte_array_value: [],
                bool_array_value: [],
                double_array_value: [],
                string_array_value: []
              }} = ParameterServer.get_parameter(node_name, namespace, "bool_param")

      assert :ok =
               ParameterServer.set_parameter(
                 node_name,
                 namespace,
                 "bool_param",
                 false
               )

      assert {:ok,
              %Rclex.Pkgs.RclInterfaces.Msg.ParameterValue{
                type: 1,
                bool_value: false,
                integer_value: 0,
                double_value: +0.0,
                string_value: "",
                integer_array_value: [],
                byte_array_value: [],
                bool_array_value: [],
                double_array_value: [],
                string_array_value: []
              }} = ParameterServer.get_parameter(node_name, namespace, "bool_param")
    end

    test "supports integer parameters", %{node_name: node_name, namespace: namespace} do
      assert :ok =
               ParameterServer.declare_parameter(node_name, namespace, "int_param",
                 type: :integer,
                 default_value: 42
               )

      assert {:ok,
              %Rclex.Pkgs.RclInterfaces.Msg.ParameterValue{
                type: 2,
                bool_value: false,
                integer_value: 42,
                double_value: +0.0,
                string_value: "",
                integer_array_value: [],
                byte_array_value: [],
                bool_array_value: [],
                double_array_value: [],
                string_array_value: []
              }} = ParameterServer.get_parameter(node_name, namespace, "int_param")

      assert :ok =
               ParameterServer.set_parameter(
                 node_name,
                 namespace,
                 "int_param",
                 -100,
                 type: :integer
               )

      assert {:ok,
              %Rclex.Pkgs.RclInterfaces.Msg.ParameterValue{
                type: 2,
                bool_value: false,
                integer_value: -100,
                double_value: +0.0,
                string_value: "",
                integer_array_value: [],
                byte_array_value: [],
                bool_array_value: [],
                double_array_value: [],
                string_array_value: []
              }} = ParameterServer.get_parameter(node_name, namespace, "int_param")
    end

    test "supports double parameters", %{node_name: node_name, namespace: namespace} do
      assert :ok =
               ParameterServer.declare_parameter(node_name, namespace, "double_param",
                 type: :float,
                 default_value: 3.14
               )

      assert {:ok,
              %Rclex.Pkgs.RclInterfaces.Msg.ParameterValue{
                type: 3,
                bool_value: false,
                integer_value: 0,
                double_value: 3.14,
                string_value: "",
                integer_array_value: [],
                byte_array_value: [],
                bool_array_value: [],
                double_array_value: [],
                string_array_value: []
              }} = ParameterServer.get_parameter(node_name, namespace, "double_param")

      assert :ok =
               ParameterServer.set_parameter(
                 node_name,
                 namespace,
                 "double_param",
                 -2.718
               )

      assert {:ok,
              %Rclex.Pkgs.RclInterfaces.Msg.ParameterValue{
                type: 3,
                bool_value: false,
                integer_value: 0,
                double_value: -2.718,
                string_value: "",
                integer_array_value: [],
                byte_array_value: [],
                bool_array_value: [],
                double_array_value: [],
                string_array_value: []
              }} = ParameterServer.get_parameter(node_name, namespace, "double_param")
    end

    test "supports string parameters", %{node_name: node_name, namespace: namespace} do
      assert :ok =
               ParameterServer.declare_parameter(node_name, namespace, "string_param",
                 type: :string,
                 default_value: "hello"
               )

      assert {:ok,
              %Rclex.Pkgs.RclInterfaces.Msg.ParameterValue{
                type: 4,
                bool_value: false,
                integer_value: 0,
                double_value: +0.0,
                string_value: "hello",
                integer_array_value: [],
                byte_array_value: [],
                bool_array_value: [],
                double_array_value: [],
                string_array_value: []
              }} = ParameterServer.get_parameter(node_name, namespace, "string_param")

      assert :ok =
               ParameterServer.set_parameter(
                 node_name,
                 namespace,
                 "string_param",
                 "world"
               )

      assert {:ok,
              %Rclex.Pkgs.RclInterfaces.Msg.ParameterValue{
                type: 4,
                bool_value: false,
                integer_value: 0,
                double_value: +0.0,
                string_value: "world",
                integer_array_value: [],
                byte_array_value: [],
                bool_array_value: [],
                double_array_value: [],
                string_array_value: []
              }} = ParameterServer.get_parameter(node_name, namespace, "string_param")
    end

    test "rejects type changes when dynamic_typing is false", %{
      node_name: node_name,
      namespace: namespace
    } do
      assert :ok =
               ParameterServer.declare_parameter(node_name, namespace, "strict_param",
                 type: :integer,
                 default_value: 10,
                 dynamic_typing: false
               )

      assert {:error, "wrong parameter type"} =
               ParameterServer.set_parameter(node_name, namespace, "strict_param", "nope")

      assert {:ok,
              %Rclex.Pkgs.RclInterfaces.Msg.ParameterValue{
                type: 2,
                integer_value: 10
              }} = ParameterServer.get_parameter(node_name, namespace, "strict_param")
    end

    test "allows type changes when dynamic_typing is true", %{
      node_name: node_name,
      namespace: namespace
    } do
      assert :ok =
               ParameterServer.declare_parameter(node_name, namespace, "dynamic_param",
                 type: :integer,
                 default_value: 10,
                 dynamic_typing: true
               )

      assert :ok = ParameterServer.set_parameter(node_name, namespace, "dynamic_param", "updated")

      assert {:ok,
              %Rclex.Pkgs.RclInterfaces.Msg.ParameterValue{
                type: 4,
                string_value: "updated"
              }} = ParameterServer.get_parameter(node_name, namespace, "dynamic_param")
    end

    test "atomically rejects type changes when dynamic_typing is false", %{
      node_name: node_name,
      namespace: namespace
    } do
      assert :ok =
               ParameterServer.declare_parameter(node_name, namespace, "strict_param",
                 type: :integer,
                 default_value: 10,
                 dynamic_typing: false
               )

      assert {:error, {:invalid_parameters, [{"strict_param", "wrong parameter type"}]}} =
               ParameterServer.set_parameters(
                 node_name,
                 namespace,
                 [{"strict_param", Rclex.ParameterHelpers.gen_parameter_value_struct("nope")}],
                 false,
                 true
               )

      assert {:ok,
              %Rclex.Pkgs.RclInterfaces.Msg.ParameterValue{
                type: 2,
                integer_value: 10
              }} = ParameterServer.get_parameter(node_name, namespace, "strict_param")
    end

    test "set_parameters convert=true preserves declared parameter type", %{
      node_name: node_name,
      namespace: namespace
    } do
      assert :ok =
               ParameterServer.declare_parameter(node_name, namespace, "waypoints",
                 type: :integer_array,
                 default_value: [0, 0, 0]
               )

      assert :ok =
               ParameterServer.set_parameters(
                 node_name,
                 namespace,
                 [{"waypoints", [10, 20, 30]}],
                 true,
                 true
               )

      assert {:ok,
              %Rclex.Pkgs.RclInterfaces.Msg.ParameterValue{
                type: 7,
                integer_array_value: [10, 20, 30]
              }} = ParameterServer.get_parameter(node_name, namespace, "waypoints")
    end

    test "supports byte array parameters", %{node_name: node_name, namespace: namespace} do
      bytes = [1, 2, 3, 255]

      assert :ok =
               ParameterServer.declare_parameter(
                 node_name,
                 namespace,
                 "byte_array_param",
                 type: :byte_array,
                 default_value: bytes
               )

      assert {:ok,
              %Rclex.Pkgs.RclInterfaces.Msg.ParameterValue{
                type: 5,
                bool_value: false,
                integer_value: 0,
                double_value: +0.0,
                string_value: "",
                integer_array_value: [],
                byte_array_value: ^bytes,
                bool_array_value: [],
                double_array_value: [],
                string_array_value: []
              }} = ParameterServer.get_parameter(node_name, namespace, "byte_array_param")

      new_bytes = [100, 200]

      assert :ok =
               ParameterServer.set_parameter(
                 node_name,
                 namespace,
                 "byte_array_param",
                 new_bytes,
                 type: :byte_array
               )

      assert {:ok,
              %Rclex.Pkgs.RclInterfaces.Msg.ParameterValue{
                type: 5,
                bool_value: false,
                integer_value: 0,
                double_value: +0.0,
                string_value: "",
                integer_array_value: [],
                byte_array_value: ^new_bytes,
                bool_array_value: [],
                double_array_value: [],
                string_array_value: []
              }} = ParameterServer.get_parameter(node_name, namespace, "byte_array_param")
    end

    test "supports boolean array parameters", %{node_name: node_name, namespace: namespace} do
      bools = [true, false, true]

      assert :ok =
               ParameterServer.declare_parameter(
                 node_name,
                 namespace,
                 "bool_array_param",
                 type: :boolean_array,
                 default_value: bools
               )

      assert {:ok,
              %Rclex.Pkgs.RclInterfaces.Msg.ParameterValue{
                type: 6,
                bool_value: false,
                integer_value: 0,
                double_value: +0.0,
                string_value: "",
                integer_array_value: [],
                byte_array_value: [],
                bool_array_value: ^bools,
                double_array_value: [],
                string_array_value: []
              }} = ParameterServer.get_parameter(node_name, namespace, "bool_array_param")
    end

    test "supports integer array parameters", %{node_name: node_name, namespace: namespace} do
      ints = [1, -2, 42, 1000]

      assert :ok =
               ParameterServer.declare_parameter(
                 node_name,
                 namespace,
                 "int_array_param",
                 type: :integer_array,
                 default_value: ints
               )

      assert {:ok,
              %Rclex.Pkgs.RclInterfaces.Msg.ParameterValue{
                type: 7,
                bool_value: false,
                integer_value: 0,
                double_value: +0.0,
                string_value: "",
                integer_array_value: ^ints,
                byte_array_value: [],
                bool_array_value: [],
                double_array_value: [],
                string_array_value: []
              }} = ParameterServer.get_parameter(node_name, namespace, "int_array_param")
    end

    test "supports double array parameters", %{node_name: node_name, namespace: namespace} do
      doubles = [1.1, -2.2, 3.14159]

      assert :ok =
               ParameterServer.declare_parameter(
                 node_name,
                 namespace,
                 "double_array_param",
                 type: :float_array,
                 default_value: doubles
               )

      assert {:ok,
              %Rclex.Pkgs.RclInterfaces.Msg.ParameterValue{
                type: 8,
                bool_value: false,
                integer_value: 0,
                double_value: +0.0,
                string_value: "",
                integer_array_value: [],
                byte_array_value: [],
                bool_array_value: [],
                double_array_value: ^doubles,
                string_array_value: []
              }} = ParameterServer.get_parameter(node_name, namespace, "double_array_param")
    end

    test "supports string array parameters", %{node_name: node_name, namespace: namespace} do
      strings = ["hello", "world", "ros2"]

      assert :ok =
               ParameterServer.declare_parameter(
                 node_name,
                 namespace,
                 "string_array_param",
                 type: :string_array,
                 default_value: strings
               )

      assert {:ok,
              %Rclex.Pkgs.RclInterfaces.Msg.ParameterValue{
                type: 9,
                bool_value: false,
                integer_value: 0,
                double_value: +0.0,
                string_value: "",
                integer_array_value: [],
                byte_array_value: [],
                bool_array_value: [],
                double_array_value: [],
                string_array_value: ^strings
              }} = ParameterServer.get_parameter(node_name, namespace, "string_array_param")
    end

    test "supports empty arrays", %{node_name: node_name, namespace: namespace} do
      # Empty arrays should infer as byte arrays by default
      assert :ok =
               ParameterServer.declare_parameter(node_name, namespace, "empty_array",
                 type: :byte_array,
                 default_value: []
               )

      assert {:ok,
              %Rclex.Pkgs.RclInterfaces.Msg.ParameterValue{
                type: 5,
                bool_value: false,
                integer_value: 0,
                double_value: +0.0,
                string_value: "",
                integer_array_value: [],
                byte_array_value: [],
                bool_array_value: [],
                double_array_value: [],
                string_array_value: []
              }} = ParameterServer.get_parameter(node_name, namespace, "empty_array")

      # Check type
      [type] = ParameterServer.get_parameter_types(node_name, namespace, ["empty_array"])
      assert type == :byte_array
    end
  end

  describe "parameter service handlers" do
    test "get_parameters service returns correct values", %{
      node_name: node_name,
      namespace: namespace
    } do
      # Declare test parameters
      assert :ok =
               ParameterServer.declare_parameter(node_name, namespace, "test1",
                 type: :integer,
                 default_value: 42
               )

      assert :ok =
               ParameterServer.declare_parameter(node_name, namespace, "test2",
                 type: :string,
                 default_value: "hello"
               )

      # Test service handler directly
      request = %GetParameters.Request{names: ["test1", "test2", "nonexistent"]}
      response = ParameterServer.handle_get_parameters(request, node_name, namespace)

      assert %GetParameters.Response{values: values} = response
      assert length(values) == 3

      # Check returned values
      [val1, val2, val3] = values
      assert val1.type == ParameterType.parameter_integer()
      assert val1.integer_value == 42

      assert val2.type == ParameterType.parameter_string()
      assert val2.string_value == "hello"

      assert val3.type == ParameterType.parameter_not_set()
    end

    test "set_parameters service sets parameter values", %{
      node_name: node_name,
      namespace: namespace
    } do
      # Declare test parameters
      assert :ok =
               ParameterServer.declare_parameter(node_name, namespace, "param1",
                 type: :integer,
                 default_value: 1
               )

      assert :ok =
               ParameterServer.declare_parameter(node_name, namespace, "param2",
                 type: :string,
                 default_value: "initial"
               )

      # Create parameter values to set
      param1_value = ParameterHelpers.gen_parameter_value_struct(100)
      param2_value = ParameterHelpers.gen_parameter_value_struct("updated")

      parameters = [
        ParameterHelpers.gen_parameter_struct("param1", param1_value),
        ParameterHelpers.gen_parameter_struct("param2", param2_value)
      ]

      # Simulate service call
      request = %SetParameters.Request{parameters: parameters}
      response = ParameterServer.handle_set_parameters(request, node_name, namespace)

      assert %SetParameters.Response{results: results} = response
      assert length(results) == 2

      # Check all results are successful
      Enum.each(results, fn result ->
        assert result.successful == true
        assert result.reason == ""
      end)

      # Verify parameters were updated
      assert {:ok,
              %Rclex.Pkgs.RclInterfaces.Msg.ParameterValue{
                type: 2,
                bool_value: false,
                integer_value: 100,
                double_value: +0.0,
                string_value: "",
                integer_array_value: [],
                byte_array_value: [],
                bool_array_value: [],
                double_array_value: [],
                string_array_value: []
              }} = ParameterServer.get_parameter(node_name, namespace, "param1")

      assert {:ok,
              %Rclex.Pkgs.RclInterfaces.Msg.ParameterValue{
                type: 4,
                bool_value: false,
                integer_value: 0,
                double_value: +0.0,
                string_value: "updated",
                integer_array_value: [],
                byte_array_value: [],
                bool_array_value: [],
                double_array_value: [],
                string_array_value: []
              }} = ParameterServer.get_parameter(node_name, namespace, "param2")
    end

    test "set_parameters_atomically service succeeds when all parameters exist", %{
      node_name: node_name,
      namespace: namespace
    } do
      # Declare test parameters
      assert :ok =
               ParameterServer.declare_parameter(node_name, namespace, "param1",
                 type: :integer,
                 default_value: 1
               )

      assert :ok =
               ParameterServer.declare_parameter(node_name, namespace, "param2",
                 type: :integer,
                 default_value: 2
               )

      # Create parameters to set
      param1_value = ParameterHelpers.gen_parameter_value_struct(10, :integer)
      param2_value = ParameterHelpers.gen_parameter_value_struct(20, :integer)

      parameters = [
        ParameterHelpers.gen_parameter_struct("param1", param1_value),
        ParameterHelpers.gen_parameter_struct("param2", param2_value)
      ]

      # Simulate service call
      request = %SetParametersAtomically.Request{parameters: parameters}
      response = ParameterServer.handle_set_parameters_atomically(request, node_name, namespace)

      assert %SetParametersAtomically.Response{result: result} = response
      assert result.successful == true
      assert result.reason == ""

      # Verify parameters were updated
      assert {:ok,
              %Rclex.Pkgs.RclInterfaces.Msg.ParameterValue{
                type: 2,
                bool_value: false,
                integer_value: 10,
                double_value: +0.0,
                string_value: "",
                byte_array_value: [],
                integer_array_value: [],
                bool_array_value: [],
                double_array_value: [],
                string_array_value: []
              }} = ParameterServer.get_parameter(node_name, namespace, "param1")

      assert {:ok,
              %Rclex.Pkgs.RclInterfaces.Msg.ParameterValue{
                type: 2,
                bool_value: false,
                integer_value: 20,
                double_value: +0.0,
                string_value: "",
                byte_array_value: [],
                integer_array_value: [],
                bool_array_value: [],
                double_array_value: [],
                string_array_value: []
              }} = ParameterServer.get_parameter(node_name, namespace, "param2")
    end

    test "list_parameters service returns parameter names", %{
      node_name: node_name,
      namespace: namespace
    } do
      # Declare test parameters
      assert :ok =
               ParameterServer.declare_parameter(node_name, namespace, "alpha",
                 type: :integer,
                 default_value: 1
               )

      assert :ok =
               ParameterServer.declare_parameter(node_name, namespace, "beta",
                 type: :integer,
                 default_value: 2
               )

      assert :ok =
               ParameterServer.declare_parameter(node_name, namespace, "gamma",
                 type: :integer,
                 default_value: 3
               )

      # Simulate service call - basic list
      request = %ListParameters.Request{prefixes: [], depth: 0}
      response = ParameterServer.handle_list_parameters(request, node_name, namespace)

      assert %ListParameters.Response{result: result} = response
      assert length(result.names) == 3
      assert "alpha" in result.names
      assert "beta" in result.names
      assert "gamma" in result.names
      assert result.prefixes == []
    end

    test "list_parameters service filters by prefixes", %{
      node_name: node_name,
      namespace: namespace
    } do
      # Declare test parameters with namespaced names
      assert :ok =
               ParameterServer.declare_parameter(node_name, namespace, "robot.speed",
                 type: :float,
                 default_value: 1.0
               )

      assert :ok =
               ParameterServer.declare_parameter(node_name, namespace, "robot.name",
                 type: :string,
                 default_value: "R2D2"
               )

      assert :ok =
               ParameterServer.declare_parameter(node_name, namespace, "sensor.frequency",
                 type: :integer,
                 default_value: 10
               )

      assert :ok =
               ParameterServer.declare_parameter(node_name, namespace, "robotics.speed",
                 type: :float,
                 default_value: 2.0
               )

      # Simulate service call - filter by robot prefix
      request = %ListParameters.Request{prefixes: ["robot"], depth: 0}
      response = ParameterServer.handle_list_parameters(request, node_name, namespace)

      assert %ListParameters.Response{result: result} = response
      assert length(result.names) == 2
      assert "robot.speed" in result.names
      assert "robot.name" in result.names
      refute "sensor.frequency" in result.names
      refute "robotics.speed" in result.names
      assert result.prefixes == ["robot"]
    end

    test "describe_parameters service returns descriptors", %{
      node_name: node_name,
      namespace: namespace
    } do
      # Declare parameters with descriptors
      assert :ok =
               ParameterServer.declare_parameter(node_name, namespace, "param1",
                 type: :integer,
                 default_value: 42,
                 description: "First parameter"
               )

      assert :ok =
               ParameterServer.declare_parameter(node_name, namespace, "param2",
                 type: :string,
                 default_value: "hello",
                 description: "Second parameter"
               )

      # Simulate service call
      request = %DescribeParameters.Request{names: ["param1", "param2"]}
      response = ParameterServer.handle_describe_parameters(request, node_name, namespace)

      assert %DescribeParameters.Response{descriptors: descriptors} = response
      assert length(descriptors) == 2

      # Find descriptors by name
      desc1_result = Enum.find(descriptors, &(&1.name == "param1"))
      desc2_result = Enum.find(descriptors, &(&1.name == "param2"))

      assert desc1_result.description == "First parameter"
      assert desc2_result.description == "Second parameter"
    end

    test "get_parameter_types service returns correct types", %{
      node_name: node_name,
      namespace: namespace
    } do
      # Declare parameters of different types
      assert :ok =
               ParameterServer.declare_parameter(node_name, namespace, "bool_param",
                 type: :boolean,
                 default_value: true
               )

      assert :ok =
               ParameterServer.declare_parameter(node_name, namespace, "int_param",
                 type: :integer,
                 default_value: 42
               )

      assert :ok =
               ParameterServer.declare_parameter(node_name, namespace, "string_param",
                 type: :string,
                 default_value: "hello"
               )

      # Simulate service call
      request = %GetParameterTypes.Request{
        names: ["bool_param", "int_param", "string_param", "nonexistent"]
      }

      response = ParameterServer.handle_get_parameter_types(request, node_name, namespace)

      assert %GetParameterTypes.Response{types: types} = response
      assert byte_size(types) == 4

      # Check returned types (as ROS2 integer constants)
      <<bool_type, int_type, string_type, not_set_type>> = types
      assert bool_type == ParameterType.parameter_bool()
      assert int_type == ParameterType.parameter_integer()
      assert string_type == ParameterType.parameter_string()
      assert not_set_type == ParameterType.parameter_not_set()
    end
  end

  describe "integration with ParameterHelpers" do
    test "parameter equality works correctly", %{node_name: node_name, namespace: namespace} do
      # Declare parameter
      assert :ok =
               ParameterServer.declare_parameter(node_name, namespace, "test_param",
                 type: :integer,
                 default_value: 42
               )

      # Get parameter value structs
      server = ParameterServer.name(node_name, namespace)
      state = :sys.get_state(server)
      param_value = Map.get(state.parameters, "test_param")

      # Create equivalent parameter value
      equivalent_value = ParameterHelpers.gen_parameter_value_struct(42)

      # Should be equal
      assert ParameterHelpers.parameter_values_equal?(param_value, equivalent_value)

      # Create different parameter value
      different_value = ParameterHelpers.gen_parameter_value_struct(100)

      # Should not be equal
      refute ParameterHelpers.parameter_values_equal?(param_value, different_value)
    end
  end

  describe "error handling" do
    test "handles callback exceptions gracefully", %{node_name: node_name, namespace: namespace} do
      # Add a callback that raises an exception
      bad_callback = fn _name, _new_value, _old_value ->
        raise "Callback error"
      end

      assert :ok =
               ParameterServer.add_post_set_parameters_callback(
                 node_name,
                 namespace,
                 bad_callback
               )

      # This should not crash the parameter server
      capture_log(fn ->
        # Parameter changes should still work despite callback error
        assert :ok =
                 ParameterServer.declare_parameter(node_name, namespace, "test_param",
                   type: :string,
                   default_value: "initial"
                 )

        assert :ok =
                 ParameterServer.set_parameter(
                   node_name,
                   namespace,
                   "test_param",
                   "updated"
                 )
      end)

      # Verify parameter was still updated
      assert {:ok,
              %Rclex.Pkgs.RclInterfaces.Msg.ParameterValue{
                type: 4,
                bool_value: false,
                integer_value: 0,
                double_value: +0.0,
                string_value: "updated",
                integer_array_value: [],
                byte_array_value: [],
                bool_array_value: [],
                double_array_value: [],
                string_array_value: []
              }} = ParameterServer.get_parameter(node_name, namespace, "test_param")
    end

    test "handles invalid parameter names", %{node_name: node_name, namespace: namespace} do
      # Test empty parameter name
      assert {:error, _} =
               ParameterServer.declare_parameter(node_name, namespace, "",
                 type: :integer,
                 default_value: 42
               )

      # Test parameter name with invalid characters (if validation exists)
      # This may depend on ROS2 parameter name validation rules
    end

    test "handles very large parameter values", %{node_name: node_name, namespace: namespace} do
      # Test large array
      large_array = Enum.to_list(1..1000)

      assert :ok =
               ParameterServer.declare_parameter(
                 node_name,
                 namespace,
                 "large_array",
                 type: :integer_array,
                 default_value: large_array
               )

      assert {:ok,
              %Rclex.Pkgs.RclInterfaces.Msg.ParameterValue{
                type: 7,
                bool_value: false,
                integer_value: 0,
                double_value: +0.0,
                string_value: "",
                integer_array_value: ^large_array,
                byte_array_value: [],
                bool_array_value: [],
                double_array_value: [],
                string_array_value: []
              }} = ParameterServer.get_parameter(node_name, namespace, "large_array")

      # Test very long string
      long_string = String.duplicate("a", 10_000)

      assert :ok =
               ParameterServer.declare_parameter(node_name, namespace, "long_string",
                 type: :string,
                 default_value: long_string
               )

      assert {:ok,
              %Rclex.Pkgs.RclInterfaces.Msg.ParameterValue{
                type: 4,
                bool_value: false,
                integer_value: 0,
                double_value: +0.0,
                string_value: ^long_string,
                integer_array_value: [],
                byte_array_value: [],
                bool_array_value: [],
                double_array_value: [],
                string_array_value: []
              }} = ParameterServer.get_parameter(node_name, namespace, "long_string")
    end
  end

  describe "GenServer callbacks" do
    test "server terminates cleanly", %{node_name: node_name, namespace: namespace} do
      server = ParameterServer.name(node_name, namespace)
      server_pid = GenServer.whereis(server)
      assert Process.alive?(server_pid)

      # Terminate the parameter server
      capture_log(fn ->
        GenServer.stop(server_pid, :shutdown)
      end)

      # Give it time to terminate
      Process.sleep(50)

      # Should be terminated
      refute Process.alive?(server_pid)
    end

    test "init creates proper initial state", %{node_name: node_name, namespace: namespace} do
      server = ParameterServer.name(node_name, namespace)
      state = :sys.get_state(server)

      assert state.name == node_name
      assert state.namespace == namespace
      assert state.parameters == %{}
      assert state.parameter_descriptors == %{}
      assert state.pre_set_parameters_callbacks == []
      assert state.on_set_parameters_callbacks == []
      assert state.post_set_parameters_callbacks == []
      assert state.parameter_event_publisher != nil
      assert state.parameter_event_descriptors_publisher != nil
    end
  end

  describe "parameter name validation" do
    test "validates parameter names according to ROS2 rules", %{
      node_name: node_name,
      namespace: namespace
    } do
      # Valid parameter names
      valid_names = [
        "simple_param",
        "param123",
        "my.nested.param",
        "robot_speed",
        "sensor_data.frequency"
      ]

      Enum.each(valid_names, fn name ->
        assert :ok =
                 ParameterServer.declare_parameter(node_name, namespace, name, default_value: 42)
      end)

      # Get all parameters to verify they were declared
      param_names = ParameterServer.list_parameters(node_name, namespace)

      Enum.each(valid_names, fn name ->
        assert name in param_names
      end)
    end
  end

  describe "concurrent access" do
    test "handles concurrent parameter operations", %{node_name: node_name, namespace: namespace} do
      # Declare initial parameter
      assert :ok =
               ParameterServer.declare_parameter(node_name, namespace, "concurrent_param",
                 type: :integer,
                 default_value: 0
               )

      # Spawn multiple tasks that modify the parameter
      tasks =
        for i <- 1..10 do
          Task.async(fn ->
            ParameterServer.set_parameter(
              node_name,
              namespace,
              "concurrent_param",
              i
            )
          end)
        end

      # Wait for all tasks to complete
      results = Task.await_many(tasks)

      # All operations should succeed
      Enum.each(results, fn result ->
        assert result == :ok
      end)

      # Parameter should have some final value
      assert {:ok, _final_value} =
               ParameterServer.get_parameter(node_name, namespace, "concurrent_param")
    end
  end
end
