defmodule Rclex.RobotStatePublisherTest do
  use ExUnit.Case, async: false

  alias Rclex.RobotStatePublisher, as: Publisher

  setup do
    Process.flag(:trap_exit, true)
    :ok = Application.ensure_started(:rclex)
    name = "rsp_#{System.unique_integer([:positive])}"
    {:ok, model} = Rclex.Urdf.parse_string(robot())
    %{name: name, model: model}
  end

  test "JointState transport reaches the native composed TF2 chain", ctx do
    server = start_publisher(ctx)
    listener(ctx)
    type = message_type("SensorMsgs", "JointState")
    assert :ok = Rclex.start_publisher(type, "/joint_states", ctx.name)
    message = joint_state(["slide"], [2.0], 10)
    assert :ok = Rclex.publish(message, "/joint_states", ctx.name)
    found = lookup(ctx, "base", "tool", 10_000_000_000)
    assert_in_delta found.transform.translation.x, 3.0, 1.0e-9
    assert Process.alive?(server)
  end

  @tag :tmp_dir
  test "included Xacro descriptions flow through the publisher into TF2", ctx do
    File.write!(Path.join(ctx.tmp_dir, "parts.xacro"), robot())
    path = Path.join(ctx.tmp_dir, "robot.urdf.xacro")

    File.write!(path, """
    <robot name="included_robot" xmlns:xacro="http://www.ros.org/wiki/xacro">
      <xacro:include filename="parts.xacro"/>
    </robot>
    """)

    assert {:ok, model} = Rclex.Urdf.parse_file(path)
    assert model.name == "included_robot"
    server = start_publisher(%{ctx | model: model})
    listener(ctx)
    assert :ok = Publisher.publish_joint_state(server, joint_state(["slide"], [4.0], 10))

    assert_in_delta lookup(ctx, "base", "tool", 10_000_000_000).transform.translation.x,
                    5.0,
                    1.0e-9
  end

  test "late listener receives every static edge in one durable sample", ctx do
    start_publisher(ctx)
    listener(ctx)
    found = lookup(ctx, "base", "mount2", 99_000_000_000)
    assert_in_delta found.transform.translation.x, 2.0, 1.0e-9
  end

  test "partial updates do not fabricate or restamp absent joints", ctx do
    server = start_publisher(ctx)
    listener(ctx)
    assert :ok = Publisher.publish_joint_state(server, joint_state(["slide"], [2.0], 10))
    lookup(ctx, "mount", "tool", 10_000_000_000)
    assert :ok = Publisher.publish_joint_state(server, joint_state(["turn"], [0.5], 20))
    lookup(ctx, "base", "rotor", 20_000_000_000)

    assert {:error, :extrapolation} =
             Rclex.Tf2.lookup_transform("rsp", "mount", "tool", 20_000_000_000, 0.0, ctx.name)

    assert {:error, :lookup} =
             Rclex.Tf2.lookup_transform("rsp", "base", "unused", 0, 0.0, ctx.name)
  end

  test "malformed updates are rejected atomically including unknown joints", ctx do
    server = start_publisher(ctx)
    valid = joint_state(["slide"], [1.0], 10)

    invalid = [
      %{valid | position: []},
      %{valid | name: ["slide", "slide"], position: [1.0, 2.0]},
      %{valid | name: [:slide]},
      %{valid | position: ["bad"]},
      %{valid | position: [Integer.pow(10, 400)]},
      %{valid | name: ["unknown"], position: ["bad"]},
      %{valid | velocity: [0.0, 1.0]},
      %{valid | velocity: [Integer.pow(10, 400)]},
      %{valid | effort: [:bad]},
      %{valid | effort: [Integer.pow(10, 400)]},
      put_in(valid.header.stamp.sec, -1),
      put_in(valid.header.stamp.sec, 2_147_483_648),
      put_in(valid.header.stamp.nanosec, 1_000_000_000),
      %{}
    ]

    for message <- invalid do
      assert {:error, _} = Publisher.publish_joint_state(server, message)
    end

    assert :ok =
             Publisher.publish_joint_state(server, joint_state(["slide", "unknown"], [1, 2], 1))

    assert :ok = Publisher.publish_joint_state(server, joint_state([], [], 0))
    assert :ok = Publisher.publish_joint_state(server, joint_state(["unknown"], [1.0e308], 0))
  end

  test "timestamps are per joint, allow equal and reject backwards atomically", ctx do
    server = start_publisher(ctx)
    assert :ok = Publisher.publish_joint_state(server, joint_state(["slide"], [1.0], 10))
    assert :ok = Publisher.publish_joint_state(server, joint_state(["turn"], [0.2], 1))
    assert :ok = Publisher.publish_joint_state(server, joint_state(["slide"], [2.0], 10))

    assert {:error, {:backwards_stamp, rejected}} =
             Publisher.publish_joint_state(server, joint_state(["turn", "slide"], [0.3, 3.0], 9))

    assert rejected in ["slide", "copy"]
    assert :ok = Publisher.publish_joint_state(server, joint_state(["turn"], [0.4], 2))
  end

  test "mimics derive position and stamp from this update's source", ctx do
    server = start_publisher(ctx)
    listener(ctx)

    assert :ok =
             Publisher.publish_joint_state(
               server,
               joint_state(["slide", "copy"], [2.0, 99.0], 10)
             )

    found = lookup(ctx, "base", "follower", 10_000_000_000)
    assert_in_delta found.transform.translation.x, 5.0, 1.0e-9
    assert found.header.stamp.sec == 10
    assert :ok = Publisher.publish_joint_state(server, joint_state(["copy"], [8.0], 20))

    assert {:error, :extrapolation} =
             Rclex.Tf2.lookup_transform("rsp", "base", "follower", 20_000_000_000, 0.0, ctx.name)
  end

  test "namespace, relative JointState topic and frame prefix are independent", ctx do
    ctx = Map.put(ctx, :namespace, "/robot")
    server = start_publisher(ctx, joint_states_topic: "joint_states", frame_prefix: "robot/")
    listener(ctx)
    assert :ok = Publisher.publish_joint_state(server, joint_state(["slide"], [2.0], 10))
    found = lookup(ctx, "robot/base", "robot/tool", 10_000_000_000)
    assert_in_delta found.transform.translation.x, 3.0, 1.0e-9
    assert GenServer.whereis(Rclex.Node.name(ctx.name, "/robot"))
  end

  test "owned shutdown removes the node and its entities", ctx do
    start_publisher(ctx)
    stop_supervised!(Publisher)
    assert GenServer.whereis(Rclex.Node.name(ctx.name)) == nil
    assert Rclex.get_local_entities(name: ctx.name) == []
  end

  test "borrowed shutdown removes only its subscription", ctx do
    assert :ok = Rclex.start_node(ctx.name)
    on_exit(fn -> Rclex.stop_node(ctx.name) end)
    assert :ok = Rclex.Tf2.start_broadcaster(ctx.name)
    before = Rclex.get_local_entities(name: ctx.name)
    start_publisher(ctx, node_mode: :borrow)
    stop_supervised!(Publisher)
    assert GenServer.whereis(Rclex.Node.name(ctx.name))
    assert Enum.sort(Rclex.get_local_entities(name: ctx.name)) == Enum.sort(before)
    assert :ok = Rclex.Tf2.broadcast_static([], ctx.name)
  end

  test "borrowed startup never adopts an existing JointState subscription", ctx do
    assert :ok = Rclex.start_node(ctx.name)
    on_exit(fn -> Rclex.stop_node(ctx.name) end)
    assert :ok = Rclex.Tf2.start_broadcaster(ctx.name)
    type = message_type("SensorMsgs", "JointState")
    assert :ok = Rclex.start_subscription(fn _ -> :ok end, type, "/joint_states", ctx.name)
    subscription = GenServer.whereis(Rclex.Subscription.name(type, "/joint_states", ctx.name))

    assert {:error, :already_started} =
             Publisher.start_link(model: ctx.model, node_name: ctx.name, node_mode: :borrow)

    assert Process.alive?(subscription)
  end

  test "borrowed shutdown preserves a replacement subscription", ctx do
    assert :ok = Rclex.start_node(ctx.name)
    on_exit(fn -> Rclex.stop_node(ctx.name) end)
    assert :ok = Rclex.Tf2.start_broadcaster(ctx.name)
    server = start_publisher(ctx, node_mode: :borrow)
    original = :sys.get_state(server).subscription_pid
    assert :ok = GenServer.stop(original)
    type = message_type("SensorMsgs", "JointState")
    assert :ok = Rclex.start_subscription(fn _ -> :ok end, type, "/joint_states", ctx.name)
    replacement = GenServer.whereis(Rclex.Subscription.name(type, "/joint_states", ctx.name))
    stop_supervised!(Publisher)
    assert Process.alive?(replacement)
  end

  test "unsupported joints fail before creating resources", ctx do
    for kind <- ["planar", "floating"] do
      {:ok, model} =
        Rclex.Urdf.parse_string(
          robot()
          |> String.replace(
            "name=\"slide\" type=\"prismatic\"",
            "name=\"slide\" type=\"#{kind}\""
          )
          |> String.replace(~s(<mimic joint="slide" multiplier="2" offset="1"/>), "")
        )

      assert {:error, {:unsupported_joint, "slide", _}} =
               Publisher.start_link(model: model, node_name: ctx.name)

      assert GenServer.whereis(Rclex.Node.name(ctx.name)) == nil
    end
  end

  test "node death terminates the worker", ctx do
    server = start_publisher(ctx)
    Process.unlink(server)
    monitor = Process.monitor(server)
    assert :ok = Rclex.stop_node(ctx.name)
    assert_receive {:DOWN, ^monitor, :process, ^server, {:node_down, _}}, 2_000
  end

  test "supervisor recreates working transport after owned node loss", ctx do
    server = start_publisher(ctx)
    monitor = Process.monitor(server)
    assert :ok = Rclex.stop_node(ctx.name)
    assert_receive {:DOWN, ^monitor, :process, ^server, {:node_down, _}}, 2_000
    replacement = await_worker(server)
    listener(ctx)
    assert :ok = Publisher.publish_joint_state(replacement, joint_state(["slide"], [4.0], 10))
    found = lookup(ctx, "base", "tool", 10_000_000_000)
    assert_in_delta found.transform.translation.x, 5.0, 1.0e-9
  end

  test "killing the actual node retires its owned supervisor and stale TF cache", ctx do
    server = start_publisher(ctx)
    owned = GenServer.whereis(Rclex.NodeSupervisor.name(ctx.name))
    owned_monitor = Process.monitor(owned)
    node = GenServer.whereis(Rclex.Node.name(ctx.name))
    type = message_type("Tf2Msgs", "TFMessage")
    old_static = GenServer.whereis(Rclex.Publisher.name(type, "/tf_static", ctx.name))
    Process.exit(node, :kill)

    assert_receive {:DOWN, ^owned_monitor, :process, ^owned, _}, 2_000
    replacement = await_worker(server)
    assert GenServer.whereis(Rclex.NodeSupervisor.name(ctx.name)) != owned
    new_static = GenServer.whereis(Rclex.Publisher.name(type, "/tf_static", ctx.name))
    assert is_pid(new_static) and new_static != old_static
    listener(ctx)
    assert lookup(ctx, "base", "mount2", 0).transform.translation.x == 2.0
    assert :ok = Publisher.publish_joint_state(replacement, joint_state(["slide"], [4.0], 10))
    assert lookup(ctx, "base", "tool", 10_000_000_000).transform.translation.x == 5.0
  end

  test "borrowed node without a broadcaster fails without adding entities", ctx do
    assert :ok = Rclex.start_node(ctx.name)
    on_exit(fn -> Rclex.stop_node(ctx.name) end)
    before = Rclex.get_local_entities(name: ctx.name)

    assert {:error, :broadcaster_not_found} =
             Publisher.start_link(model: ctx.model, node_name: ctx.name, node_mode: :borrow)

    assert Enum.sort(Rclex.get_local_entities(name: ctx.name)) == Enum.sort(before)
  end

  test "owned cleanup cannot stop a replacement while TF2 teardown is queued", ctx do
    {:ok, server} = Publisher.start_link(model: ctx.model, node_name: ctx.name)
    Process.unlink(server)
    monitor = Process.monitor(server)
    tf2 = Process.whereis(Rclex.Tf2)
    :ok = :sys.suspend(tf2)
    on_exit(fn -> :sys.resume(tf2) end)
    :erlang.trace(server, true, [:send])
    stopper = Task.async(fn -> GenServer.stop(server) end)

    receive do
      {:trace, ^server, :send, {:"$gen_call", _, {:stop_broadcaster, _, _}}, ^tf2} -> :ok
      {:DOWN, ^monitor, :process, ^server, :normal} -> :ok
    after
      2_000 -> flunk("cleanup neither completed nor queued TF2 teardown")
    end

    Rclex.stop_node(ctx.name)
    assert :ok = Rclex.start_node(ctx.name)
    on_exit(fn -> Rclex.stop_node(ctx.name) end)
    replacement = GenServer.whereis(Rclex.NodeSupervisor.name(ctx.name))
    type = message_type("Tf2Msgs", "TFMessage")
    assert :ok = Rclex.start_publisher(type, "/tf", ctx.name)
    assert :ok = Rclex.start_publisher(type, "/tf_static", ctx.name)
    dynamic = GenServer.whereis(Rclex.Publisher.name(type, "/tf", ctx.name))
    static = GenServer.whereis(Rclex.Publisher.name(type, "/tf_static", ctx.name))
    :ok = :sys.resume(tf2)
    assert :ok = Task.await(stopper)
    assert Process.alive?(replacement)
    assert Process.alive?(dynamic)
    assert Process.alive?(static)
  end

  test "timed out borrowed startup cleans a late subscription acquisition", ctx do
    assert_late_subscription_cleanup(ctx, false)
  end

  test "late borrowed acquisition never stops a preexisting subscription", ctx do
    assert_late_subscription_cleanup(ctx, true)
  end

  test "invalid options and existing owned nodes are not adopted", ctx do
    for opts <- [
          [node_mode: :invalid],
          [node_name: ""],
          [node_name: nil],
          [namespace: "relative"],
          [namespace: nil],
          [frame_prefix: "/bad"],
          [joint_states_topic: nil],
          [joint_states_topic: ""]
        ] do
      assert {:error, _} =
               Publisher.start_link(Keyword.merge([model: ctx.model, node_name: ctx.name], opts))

      assert GenServer.whereis(Rclex.Node.name(ctx.name)) == nil
    end

    assert :ok = Rclex.start_node(ctx.name)
    on_exit(fn -> Rclex.stop_node(ctx.name) end)
    node = GenServer.whereis(Rclex.Node.name(ctx.name))

    assert {:error, :already_started} =
             Publisher.start_link(model: ctx.model, node_name: ctx.name)

    assert Process.alive?(node)
  end

  test "failure after creating a dynamic publisher rolls back the owned node", ctx do
    assert {:error, _} =
             Publisher.start_link(model: ctx.model, node_name: ctx.name, tf_static_qos: :invalid)

    assert GenServer.whereis(Rclex.Node.name(ctx.name)) == nil
    assert Rclex.get_local_entities(name: ctx.name) == []
    start_publisher(ctx, joint_states_qos: Rclex.QoS.profile_default())
    listener(ctx)
    assert lookup(ctx, "base", "mount2", 0).transform.translation.x == 2.0
  end

  defp assert_late_subscription_cleanup(ctx, preexisting?) do
    assert :ok = Rclex.start_node(ctx.name)
    on_exit(fn -> Rclex.stop_node(ctx.name) end)
    assert :ok = Rclex.Tf2.start_broadcaster(ctx.name)
    type = message_type("SensorMsgs", "JointState")

    if preexisting? do
      assert :ok = Rclex.start_subscription(fn _ -> :ok end, type, "/joint_states", ctx.name)
    end

    registration = Rclex.Subscription.name(type, "/joint_states", ctx.name)
    original = GenServer.whereis(registration)
    node = GenServer.whereis(Rclex.Node.name(ctx.name))
    :ok = :sys.suspend(node)
    on_exit(fn -> if Process.alive?(node), do: :sys.resume(node) end)

    starter =
      Task.async(fn ->
        Process.flag(:trap_exit, true)
        Publisher.start_link(model: ctx.model, node_name: ctx.name, node_mode: :borrow)
      end)

    assert {:error, :subscription_start_timeout} = Task.await(starter, 7_000)
    {:messages, messages} = Process.info(node, :messages)

    guardian =
      Enum.find_value(messages, fn
        {:"$gen_call", {pid, _}, {:start_subscription, _, ^type, "/joint_states", _}} -> pid
        _ -> nil
      end)

    assert is_pid(guardian)
    monitor = Process.monitor(guardian)
    :ok = :sys.resume(node)
    GenServer.call(node, {:count_subscribers, "/joint_states"})
    assert_receive {:DOWN, ^monitor, :process, ^guardian, _}, 2_000
    assert GenServer.whereis(registration) == original
    assert Process.alive?(node)
    assert :ok = Rclex.Tf2.broadcast_static([], ctx.name)
  end

  defp await_worker(previous, attempts \\ 100)
  defp await_worker(_previous, 0), do: flunk("publisher did not restart")

  defp await_worker(previous, attempts) do
    case Supervisor.which_children(fetch_test_supervisor()) do
      children ->
        case List.keyfind(children, Publisher, 0) do
          {Publisher, pid, _, _} when is_pid(pid) and pid != previous ->
            :sys.get_state(pid)
            pid

          _ ->
            receive do
            after
              10 -> await_worker(previous, attempts - 1)
            end
        end
    end
  end

  defp fetch_test_supervisor do
    {:ok, supervisor} = ExUnit.fetch_test_supervisor()
    supervisor
  end

  defp start_publisher(ctx, opts \\ []) do
    namespace = Map.get(ctx, :namespace, "/")

    server =
      start_supervised!(
        {Publisher,
         Keyword.merge([model: ctx.model, node_name: ctx.name, namespace: namespace], opts)}
      )

    server
  end

  defp listener(ctx) do
    opts = [namespace: Map.get(ctx, :namespace, "/")]
    assert :ok = Rclex.Tf2.buffer_new("rsp", ctx.name, opts)
    assert :ok = Rclex.Tf2.start_listener("rsp", ctx.name, opts)
    on_exit(fn -> Rclex.Tf2.buffer_destroy("rsp", ctx.name, opts) end)
  end

  defp lookup(ctx, parent, child, time) do
    assert {:ok, found} =
             Rclex.Tf2.lookup_transform("rsp", parent, child, time, 2.0, ctx.name,
               namespace: Map.get(ctx, :namespace, "/")
             )

    found
  end

  defp joint_state(names, positions, sec) do
    struct(message_type("SensorMsgs", "JointState"),
      header:
        struct(message_type("StdMsgs", "Header"),
          stamp: struct(message_type("BuiltinInterfaces", "Time"), sec: sec)
        ),
      name: names,
      position: positions,
      velocity: [],
      effort: []
    )
  end

  defp message_type(package, name), do: Module.concat(["Rclex", "Pkgs", package, "Msg", name])

  defp robot do
    """
    <robot name="test">
      <link name="base"/><link name="mount"/><link name="mount2"/>
      <link name="tool"/><link name="rotor"/><link name="follower"/><link name="unused"/>
      <joint name="fixed1" type="fixed"><parent link="base"/><child link="mount"/><origin xyz="1 0 0"/></joint>
      <joint name="fixed2" type="fixed"><parent link="mount"/><child link="mount2"/><origin xyz="1 0 0"/></joint>
      <joint name="slide" type="prismatic"><parent link="mount"/><child link="tool"/><axis xyz="1 0 0"/><limit lower="-100" upper="100" effort="1" velocity="1"/></joint>
      <joint name="turn" type="continuous"><parent link="base"/><child link="rotor"/><axis xyz="0 0 1"/></joint>
      <joint name="copy" type="prismatic"><parent link="base"/><child link="follower"/><axis xyz="1 0 0"/><limit lower="-100" upper="100" effort="1" velocity="1"/><mimic joint="slide" multiplier="2" offset="1"/></joint>
      <joint name="absent" type="continuous"><parent link="base"/><child link="unused"/></joint>
    </robot>
    """
  end
end
