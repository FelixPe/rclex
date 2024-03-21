defmodule Rclex.GraphTest do
  use ExUnit.Case

  import ExUnit.CaptureLog

  alias Rclex.Nif
  alias Rclex.Graph
  alias Rclex.Pkgs.StdMsgs

  setup do
    capture_log(fn -> Application.stop(:rclex) end)

    name = ~c"name"
    namespace = ~c"/namespace"
    non_existent = ~c"does_not_exist"
    topic_name = ~c"/chatter"

    context = Nif.rcl_init!()
    node = Nif.rcl_node_init!(context, name, namespace)

    type_support = apply(StdMsgs.Msg.String, :type_support!, [])
    qos = Rclex.QoS.profile_default()
    publisher = Nif.rcl_publisher_init!(node, type_support, topic_name, qos)
    subscription = Nif.rcl_subscription_init!(node, type_support, topic_name, qos)
    :timer.sleep(50)

    on_exit(fn ->
      :ok = Nif.rcl_publisher_fini!(publisher, node)
      :ok = Nif.rcl_subscription_fini!(subscription, node)
      :ok = Nif.rcl_node_fini!(node)
      :ok = Nif.rcl_fini!(context)
    end)

    %{
      context: context,
      node: node,
      name: name,
      non_existent: non_existent,
      namespace: namespace,
      topic_name: topic_name
    }
  end

  test "count_publishers/2", %{node: node, topic_name: topic_name} do
    assert 1 = Graph.count_publishers(node, topic_name)
  end

  test "count_subscribers/2", %{node: node, topic_name: topic_name} do
    assert 1 = Graph.count_subscribers(node, topic_name)
  end

  test "get_node_names/1", %{node: node, name: name, namespace: namespace} do
    assert [{^name, ^namespace}] = Graph.get_node_names(node)
  end

  test "get_node_names_with_enclaves/1", %{node: node, name: name, namespace: namespace} do
    assert [{^name, ^namespace, ~c"/"}] = Graph.get_node_names_with_enclaves(node)
  end

  test "get_publisher_names_and_types_by_node/1", %{
    topic_name: topic_name,
    node: node,
    name: name,
    non_existent: non_existent,
    namespace: namespace
  } do
    assert [{^topic_name, [~c"std_msgs/msg/String"]}] =
             Graph.get_publisher_names_and_types_by_node(node, name, namespace, false)

    assert [{~c"rt/chatter", [~c"std_msgs::msg::dds_::String_"]}] =
             Graph.get_publisher_names_and_types_by_node(node, name, namespace, true)

    assert {:error, :not_found} =
             Graph.get_publisher_names_and_types_by_node(node, non_existent, namespace, false)
  end

  test "get_publishers_info_by_topic/3", %{
    topic_name: topic_name,
    node: node
  } do
    [info] = Graph.get_publishers_info_by_topic(node, topic_name, false)

    assert is_binary(info.endpoint_gid)
    %qos_type{} = info.qos_profile
    assert qos_type == Rclex.QoS

    assert %{
             node_name: ~c"name",
             node_namespace: ~c"/namespace",
             topic_type: ~c"std_msgs/msg/String",
             endpoint_type: :publisher
           } == Map.drop(info, [:endpoint_gid, :qos_profile])

    assert [] = Graph.get_publishers_info_by_topic(node, ~c"/does_not_exist", false)

    [info] = Graph.get_publishers_info_by_topic(node, ~c"rt/chatter", true)
    assert is_binary(info.endpoint_gid)
    %qos_type{} = info.qos_profile
    assert qos_type == Rclex.QoS

    assert %{
             node_name: ~c"name",
             node_namespace: ~c"/namespace",
             topic_type: ~c"std_msgs::msg::dds_::String_",
             endpoint_type: :publisher
           } == Map.drop(info, [:endpoint_gid, :qos_profile])
  end

  test "get_subscriber_names_and_types_by_node/1", %{
    node: node,
    name: name,
    topic_name: topic_name,
    non_existent: non_existent,
    namespace: namespace
  } do
    assert [{^topic_name, [~c"std_msgs/msg/String"]}] =
             Graph.get_subscriber_names_and_types_by_node(node, name, namespace, false)

    assert [{~c"rt/chatter", [~c"std_msgs::msg::dds_::String_"]}] =
             Graph.get_subscriber_names_and_types_by_node(node, name, namespace, true)

    assert {:error, :not_found} =
             Graph.get_subscriber_names_and_types_by_node(node, non_existent, namespace, false)
  end

  test "get_subscribers_info_by_topic/3", %{
    topic_name: topic_name,
    node: node
  } do
    [info] = Graph.get_subscribers_info_by_topic(node, topic_name, false)

    assert is_binary(info.endpoint_gid)
    %qos_type{} = info.qos_profile
    assert qos_type == Rclex.QoS

    assert %{
             node_name: ~c"name",
             node_namespace: ~c"/namespace",
             topic_type: ~c"std_msgs/msg/String",
             endpoint_type: :subscription
           } == Map.drop(info, [:endpoint_gid, :qos_profile])

    assert [] = Graph.get_subscribers_info_by_topic(node, ~c"/does_not_exist", false)

    [info] = Graph.get_subscribers_info_by_topic(node, ~c"rt/chatter", true)
    assert is_binary(info.endpoint_gid)
    %qos_type{} = info.qos_profile
    assert qos_type == Rclex.QoS

    assert %{
             node_name: ~c"name",
             node_namespace: ~c"/namespace",
             topic_type: ~c"std_msgs::msg::dds_::String_",
             endpoint_type: :subscription
           } == Map.drop(info, [:endpoint_gid, :qos_profile])
  end

  test "get_topic_names_and_types/1", %{topic_name: topic_name, node: node} do
    assert [{^topic_name, [~c"std_msgs/msg/String"]}] =
             Graph.get_topic_names_and_types(node, false)
  end
end
