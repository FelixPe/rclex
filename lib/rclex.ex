defmodule Rclex do
  @moduledoc """
  User API for `#{__MODULE__}`.
  """

  @namespace_doc "`:namespace` must lead with \"/\". if not specified, the default is \"/\""
  @qos_doc "`:qos` if not specified, applied the default which equals return of `Rclex.QoS.profile_default/0`"
  @topic_name_doc "`topic_name` must lead with \"/\". See all [constraints](https://design.ros2.org/articles/topic_and_service_names.html#ros-2-topic-and-service-name-constraints)"
  @service_name_doc "`service_name` must lead with \"/\". See all [constraints](https://design.ros2.org/articles/topic_and_service_names.html#ros-2-topic-and-service-name-constraints)"
  @no_demangle_doc "`:no_demangle` if `true`, return all topics without any demangling. if not specified, the default is `false`"
  @no_mangle_doc "`:no_mangle` if `true`, `topic_name` needs to be a valid middleware topic name, otherwise it should be a valid ROS topic name. if not specified, the default is `false`"

  @typedoc "#{@topic_name_doc}."
  @type topic_name :: String.t()

  @typedoc "#{@service_name_doc}."
  @type service_name :: String.t()

  @doc """
  Start node.

  ### opts

  - #{@namespace_doc}

  ## Examples

      iex> Rclex.start_node("node", namespace: "/example")
      :ok
      iex> Rclex.start_node("node", namespace: "/example")
      {:error, :already_started}
  """
  @spec start_node(name :: String.t(), opts :: [namespace: String.t()]) ::
          :ok | {:error, :already_started} | {:error, term()}
  def start_node(name, opts \\ []) when is_binary(name) and is_list(opts) do
    context = Rclex.Context.get()
    namespace = Keyword.get(opts, :namespace, "/")

    case Rclex.NodesSupervisor.start_child(context, name, namespace) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> {:error, :already_started}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Stop node. And also stop the entities on the node, `publisher`, `subscription` and `timer`.

  ### opts

  - #{@namespace_doc}

  ## Examples

      iex> Rclex.stop_node("node", namespace: "/example")
      :ok
      iex> Rclex.stop_node("node", namespace: "/example")
      {:error, :not_found}
  """
  @spec stop_node(name :: String.t(), opts :: [namespace: String.t()]) ::
          :ok | {:error, :not_found}
  def stop_node(name, opts \\ []) when is_binary(name) and is_list(opts) do
    namespace = Keyword.get(opts, :namespace, "/")
    Rclex.NodesSupervisor.terminate_child(name, namespace)
  end

  @doc """
  Start publisher.

  - #{@topic_name_doc}

  ## Examples

      iex> alias Rclex.Pkgs.StdMsgs
      iex> Rclex.start_publisher(StdMsgs.Msg.String, "/chatter", "node", namespace: "/example")
      :ok
      iex> Rclex.start_publisher(StdMsgs.Msg.String, "/chatter", "node", namespace: "/example")
      {:error, :already_started}
  """
  @spec start_publisher(
          message_type :: module(),
          topic_name :: topic_name(),
          node_name :: String.t(),
          opts :: [namespace: String.t(), qos: Rclex.QoS.t()]
        ) ::
          :ok | {:error, :already_started} | {:error, term()}
  def start_publisher(message_type, topic_name, node_name, opts \\ [])
      when is_atom(message_type) and is_binary(topic_name) and is_binary(node_name) and
             is_list(opts) do
    namespace = Keyword.get(opts, :namespace, "/")
    qos = Keyword.get(opts, :qos, Rclex.QoS.profile_default())

    case Rclex.Node.start_publisher(message_type, topic_name, node_name, namespace, qos) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> {:error, :already_started}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Stop publisher.

  - #{@topic_name_doc}

  ### opts

  - #{@namespace_doc}

  ## Examples

      iex> alias Rclex.Pkgs.StdMsgs
      iex> Rclex.stop_publisher(StdMsgs.Msg.String, "/chatter", "node", namespace: "/example")
      :ok
      iex> Rclex.stop_publisher(StdMsgs.Msg.String, "/chatter", "node", namespace: "/example")
      {:error, :not_found}
  """
  @spec stop_publisher(
          message_type :: module(),
          topic_name :: topic_name(),
          node_name :: String.t(),
          opts :: [namespace: String.t()]
        ) ::
          :ok | {:error, :not_found}
  def stop_publisher(message_type, topic_name, name, opts \\ [])
      when is_atom(message_type) and is_binary(topic_name) and is_binary(name) and is_list(opts) do
    namespace = Keyword.get(opts, :namespace, "/")
    Rclex.Node.stop_publisher(message_type, topic_name, name, namespace)
  end

  @doc """
  Publish message.

  - #{@topic_name_doc}

  ### opts

  - #{@namespace_doc}

  ## Examples

      iex> alias Rclex.Pkgs.StdMsgs
      iex> Rclex.publish(struct(StdMsgs.Msg.String, %{data: "hello"}), "/chatter", "node", namespace: "/example")
      :ok
      iex> Rclex.publish(struct(StdMsgs.Msg.String, %{data: "hello"}), "/chatter", "node")
      {:error, :not_found}
  """
  @spec publish(
          message :: struct(),
          topic_name :: topic_name(),
          node_name :: String.t(),
          opts :: [namespace: String.t()]
        ) :: :ok | {:error, :not_found}
  def publish(message, topic_name, node_name, opts \\ [])
      when is_struct(message) and is_binary(topic_name) and is_binary(node_name) and is_list(opts) do
    namespace = Keyword.get(opts, :namespace, "/")
    Rclex.Publisher.publish(message, topic_name, node_name, namespace)
  end

  @doc """
  Start subscription.

  - #{@topic_name_doc}

  ### opts

  - #{@namespace_doc}
  - #{@qos_doc}

  ## Examples

      iex> alias Rclex.Pkgs.StdMsgs
      iex> Rclex.start_subscription(&IO.inspect/1, StdMsgs.Msg.String, "/chatter", "node", namespace: "/example")
      :ok
      iex> Rclex.start_subscription(&IO.inspect/1, StdMsgs.Msg.String, "/chatter", "node", namespace: "/example")
      {:error, :already_started}
  """
  @spec start_subscription(
          callback :: function(),
          message_type :: module(),
          topic_name :: topic_name(),
          node_name :: String.t(),
          opts :: [namespace: String.t(), qos: Rclex.QoS.t()]
        ) ::
          :ok | {:error, :already_started} | {:error, term()}
  def start_subscription(callback, message_type, topic_name, node_name, opts \\ [])
      when is_function(callback) and is_atom(message_type) and is_binary(topic_name) and
             is_binary(node_name) and is_list(opts) do
    namespace = Keyword.get(opts, :namespace, "/")
    qos = Keyword.get(opts, :qos, Rclex.QoS.profile_default())

    case Rclex.Node.start_subscription(
           callback,
           message_type,
           topic_name,
           node_name,
           namespace,
           qos
         ) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> {:error, :already_started}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Stop subscription.

  - #{@topic_name_doc}

  ### opts

  - #{@namespace_doc}

  ## Examples

      iex> alias Rclex.Pkgs.StdMsgs
      iex> Rclex.stop_subscription(StdMsgs.Msg.String, "/chatter", "node", namespace: "/example")
      :ok
      iex> Rclex.stop_subscription(StdMsgs.Msg.String, "/chatter", "node", namespace: "/example")
      {:error, :not_found}
  """
  @spec stop_subscription(
          message_type :: module(),
          topic_name :: topic_name(),
          node_name :: String.t(),
          opts :: [namespace: String.t()]
        ) ::
          :ok | {:error, :not_found}
  def stop_subscription(message_type, topic_name, node_name, opts \\ [])
      when is_atom(message_type) and is_binary(topic_name) and is_binary(node_name) and
             is_list(opts) do
    namespace = Keyword.get(opts, :namespace, "/")
    Rclex.Node.stop_subscription(message_type, topic_name, node_name, namespace)
  end

  @doc """
    Start service.

    - #{@service_name_doc}

    ### opts

    - #{@namespace_doc}
    - #{@qos_doc}

    ## Examples

    iex> alias Rclex.Pkgs.StdSrvs
    iex> Rclex.start_service(fn _ -> %StdSrvs.Srv.SetBoolResponse{success: true} end, StdMsgs.Srv.SetBool, "/set_bool", "node", namespace: "/example")
    :ok
    iex> Rclex.start_service(fn _ -> %StdSrvs.Srv.SetBoolResponse{success: true} end, StdMsgs.Srv.SetBool, "/set_bool", "node", namespace: "/example")
    {:error, :already_started}
  """
  @spec start_service(
          callback :: function(),
          service_type :: module(),
          service_name :: service_name(),
          node_name :: String.t(),
          opts :: [namespace: String.t(), qos: Rclex.QoS.t()]
        ) ::
          :ok | {:error, :already_started} | {:error, term()}
  def start_service(callback, service_type, service_name, node_name, opts \\ [])
      when is_function(callback) and is_atom(service_type) and is_binary(service_name) and
             is_binary(node_name) and is_list(opts) do
    namespace = Keyword.get(opts, :namespace, "/")
    qos = Keyword.get(opts, :qos, Rclex.QoS.profile_services_default())

    case Rclex.Node.start_service(
           callback,
           service_type,
           service_name,
           node_name,
           namespace,
           qos
         ) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> {:error, :already_started}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Stop service.

  - #{@service_name_doc}

  ### opts

  - #{@namespace_doc}

  ## Examples

    iex> alias Rclex.Pkgs.StdSrvs
    iex> Rclex.stop_service(StdSrvs.Srvg.SetBool, "/set_bool", "node", namespace: "/example")
    :ok
    iex> Rclex.stop_service(StdSrvs.Srvg.SetBool, "/does_not_exist", "node", namespace: "/example")
    {:error, :not_found}
  """
  @spec stop_service(
          service_type :: module(),
          service_name :: service_name(),
          node_name :: String.t(),
          opts :: [namespace: String.t()]
        ) ::
          :ok | {:error, :not_found}
  def stop_service(service_type, service_name, node_name, opts \\ [])
      when is_atom(service_type) and is_binary(service_name) and is_binary(node_name) and
             is_list(opts) do
    namespace = Keyword.get(opts, :namespace, "/")
    Rclex.Node.stop_service(service_type, service_name, node_name, namespace)
  end

  @doc """
    Start client.

    - #{@service_name_doc}

    ### opts

    - #{@namespace_doc}
    - #{@qos_doc}

    ## Examples

    iex> alias Rclex.Pkgs.StdSrvs
    iex> Rclex.start_client(StdSrvs.Srv.SetBool, "/set_bool", "node", namespace: "/example")
    :ok
    iex> Rclex.start_client(StdSrvs.Srv.SetBool, "/set_bool", "node", namespace: "/example")
    {:error, :already_started}
    iex> Rclex.call(%StdSrvs.Srv.SetBoolRequest{data: true}, "/set_bool", "node", namespace: "/example"))
  """
  @spec start_client(
          callback :: function(),
          service_type :: module(),
          service_name :: service_name(),
          node_name :: String.t(),
          opts :: [namespace: String.t(), qos: Rclex.QoS.t()]
        ) ::
          :ok | {:error, :already_started} | {:error, term()}
  def start_client(callback, service_type, service_name, node_name, opts \\ [])
      when is_function(callback) and is_atom(service_type) and is_binary(service_name) and
             is_binary(node_name) and is_list(opts) do
    namespace = Keyword.get(opts, :namespace, "/")
    qos = Keyword.get(opts, :qos, Rclex.QoS.profile_services_default())

    case Rclex.Node.start_client(
           callback,
           service_type,
           service_name,
           node_name,
           namespace,
           qos
         ) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> {:error, :already_started}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
    Call service using an initialized client.

    - #{@service_name_doc}

    ### opts

    - #{@namespace_doc}

    ## Examples

    iex> alias Rclex.Pkgs.StdSrvs
    iex> Rclex.call_async(%StdSrvs.Srv.SetBoolRequest{data: true}, "/set_bool", "node", namespace: "/example")
    :ok
  """
  @spec call_async(
          request :: struct(),
          service_name :: service_name(),
          node_name :: String.t(),
          opts :: [namespace: String.t()]
        ) ::
          :ok | {:error, :not_found} | {:error, term()}
  def call_async(request, service_name, node_name, opts \\ [])
      when is_binary(service_name) and
             is_binary(node_name) and is_list(opts) do
    namespace = Keyword.get(opts, :namespace, "/")

    Rclex.Client.call_async(
      request,
      service_name,
      node_name,
      namespace
    )
  end

  @doc """
  Stop client.

  - #{@service_name_doc}

  ### opts

  - #{@namespace_doc}

  ## Examples

    iex> alias Rclex.Pkgs.StdSrvs
    iex> Rclex.stop_client(StdSrvs.Srvg.SetBool, "/set_bool", "node", namespace: "/example")
    :ok
    iex> Rclex.stop_client(StdSrvs.Srvg.SetBool, "/does_not_exist", "node", namespace: "/example")
    {:error, :not_found}
  """
  @spec stop_client(
          service_type :: module(),
          service_name :: service_name(),
          node_name :: String.t(),
          opts :: [namespace: String.t()]
        ) ::
          :ok | {:error, :not_found}
  def stop_client(service_type, service_name, node_name, opts \\ [])
      when is_atom(service_type) and is_binary(service_name) and is_binary(node_name) and
             is_list(opts) do
    namespace = Keyword.get(opts, :namespace, "/")
    Rclex.Node.stop_client(service_type, service_name, node_name, namespace)
  end

  @doc """
  Start timer.

  ### opts

  - #{@namespace_doc}

  ## Examples

      iex> Rclex.start_timer(1000, fn -> IO.inspect("tick") end, "tick", "node", namespace: "/example")
      :ok
      iex> Rclex.start_timer(1000, fn -> IO.inspect("tick") end, "tick", "node", namespace: "/example")
      {:error, :already_started}
  """
  @spec start_timer(
          period_ms :: non_neg_integer(),
          callback :: function(),
          timer_name :: String.t(),
          node_name :: String.t(),
          opts :: [namespace: String.t()]
        ) ::
          :ok | {:error, :already_started} | {:error, term()}
  def start_timer(period_ms, callback, timer_name, node_name, opts \\ [])
      when is_integer(period_ms) and is_function(callback) and is_binary(timer_name) and
             is_binary(node_name) and is_list(opts) do
    namespace = Keyword.get(opts, :namespace, "/")

    case Rclex.Node.start_timer(period_ms, callback, timer_name, node_name, namespace) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> {:error, :already_started}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Stop timer.

  ### opts

  - #{@namespace_doc}

  ## Examples

      iex> Rclex.stop_timer("tick", "node", namespace: "/example")
      :ok
      iex> Rclex.stop_timer("tick", "node", namespace: "/example")
      {:error, :not_found}
  """
  @spec stop_timer(
          timer_name :: String.t(),
          node_name :: String.t(),
          opts :: [namespace: String.t()]
        ) ::
          :ok | {:error, :not_found}
  def stop_timer(timer_name, node_name, opts \\ [])
      when is_binary(timer_name) and is_binary(node_name) and is_list(opts) do
    namespace = Keyword.get(opts, :namespace, "/")
    Rclex.Node.stop_timer(timer_name, node_name, namespace)
  end

  @doc """
  Return the number of publishers on a given topic.

  - #{@topic_name_doc}

  ### opts

  - #{@namespace_doc}

  ## Examples

      iex> alias Rclex.Pkgs.StdMsgs
      iex> Rclex.start_publisher(StdMsgs.Msg.String, "/chatter", "node", namespace: "/example")
      :ok
      iex> Rclex.count_publishers("node", "/chatter", namespace: "/example")
      1
  """
  @spec count_publishers(
          name :: String.t(),
          topic_name :: topic_name(),
          opts :: [namespace: String.t()]
        ) :: non_neg_integer()
  def count_publishers(name, topic_name, opts \\ [])
      when is_binary(name) and is_binary(topic_name) and is_list(opts) do
    namespace = Keyword.get(opts, :namespace, "/")
    Rclex.Node.count_publishers(name, namespace, topic_name)
  end

  @doc """
  Return the number of subscriptions on a given topic.

  - #{@topic_name_doc}

  ### opts

  - #{@namespace_doc}

  ## Examples

      iex> alias Rclex.Pkgs.StdMsgs
      iex> Rclex.start_subscription(&IO.inspect/1, StdMsgs.Msg.String, "/chatter", "node", namespace: "/example")
      :ok
      iex> Rclex.count_subscribers("node", "/chatter", namespace: "/example")
      1
  """
  @spec count_subscribers(
          name :: String.t(),
          topic_name :: topic_name(),
          opts :: [namespace: String.t()]
        ) :: non_neg_integer()
  def count_subscribers(name, topic_name, opts \\ [])
      when is_binary(name) and is_binary(topic_name) and is_list(opts) do
    namespace = Keyword.get(opts, :namespace, "/")
    Rclex.Node.count_subscribers(name, namespace, topic_name)
  end

  @doc """
  Return a list of discovered service client topics and its types for a remote node.

  ### opts

  - #{@namespace_doc}

  ## Examples

      iex> Rclex.get_client_names_and_types_by_node("node", "example_node", namespace: "/example")
      [{"node","/example"}]
  """
  @spec get_client_names_and_types_by_node(
          name :: String.t(),
          node_name :: String.t(),
          node_namespace :: String.t(),
          opts :: [namespace: String.t()]
        ) :: list()
  def get_client_names_and_types_by_node(
        name,
        node_name,
        node_namespace,
        opts \\ []
      )
      when is_binary(name) and is_binary(node_name) and is_binary(node_namespace) and
             is_list(opts) do
    namespace = Keyword.get(opts, :namespace, "/")
    Rclex.Node.get_client_names_and_types_by_node(name, namespace, node_name, node_namespace)
  end

  @doc """
  Return a list of available nodes in the ROS graph.

  ### opts

  - #{@namespace_doc}

  ## Examples

      iex> Rclex.get_node_names("node", namespace: "/example")
      [{"node","/example"}]
  """
  @spec get_node_names(name :: String.t(), opts :: [namespace: String.t()]) :: [
          {String.t(), String.t()}
        ]
  def get_node_names(name, opts \\ [])
      when is_binary(name) and is_list(opts) do
    namespace = Keyword.get(opts, :namespace, "/")
    Rclex.Node.get_node_names(name, namespace)
  end

  @doc """
  Return a list of available nodes in the ROS graph, including their enclave names.

  ### opts

  - #{@namespace_doc}

  ## Examples

      iex> Rclex.get_node_names_with_enclaves("node", namespace: "/example")
      [{"node", "/example", "/"}]
  """
  @spec get_node_names_with_enclaves(name :: String.t(), opts :: [namespace: String.t()]) :: [
          {String.t(), String.t(), String.t()}
        ]
  def get_node_names_with_enclaves(name, opts \\ [])
      when is_binary(name) and is_list(opts) do
    namespace = Keyword.get(opts, :namespace, "/")
    Rclex.Node.get_node_names_with_enclaves(name, namespace)
  end

  @doc """
  Return a list of topic names and types for publishers associated with a node.

  ### opts

  - #{@namespace_doc}
  - #{@no_demangle_doc}

  ## Examples

      iex> Rclex.get_publisher_names_and_types_by_node("node", "node", "/example", namespace: "/example")
      [{"/chatter", ["std_msgs/msg/String"]}]
  """
  @spec get_publisher_names_and_types_by_node(
          name :: String.t(),
          node_name :: String.t(),
          node_namespace :: String.t(),
          opts :: [namespace: String.t(), no_demangle: boolean()]
        ) :: [{String.t(), [String.t()]}] | {:error, :not_found}
  def get_publisher_names_and_types_by_node(name, node_name, node_namespace, opts \\ []) do
    namespace = Keyword.get(opts, :namespace, "/")
    no_demangle = Keyword.get(opts, :no_demangle, false)

    Rclex.Node.get_publisher_names_and_types_by_node(
      name,
      namespace,
      node_name,
      node_namespace,
      no_demangle
    )
  end

  @doc """
  Return a list of all publishers to a topic.

  ### opts

  - #{@namespace_doc}
  - #{@no_mangle_doc}

  ## Examples

      iex> Rclex.get_publishers_info_by_topic("node", "/chatter", "/example")
      [
              %{
                node_name: "node",
                node_namespace: "/example",
                topic_type: "std_msgs/msg/String",
                endpoint_type: 1,
                endpoint_gid: ...,
                qos_profile: ...
              }
      ]
  """
  @spec get_publishers_info_by_topic(
          name :: String.t(),
          topic_name :: topic_name(),
          opts :: [namespace: String.t(), no_mangle: boolean()]
        ) :: list()
  def get_publishers_info_by_topic(name, topic_name, opts \\ []) do
    namespace = Keyword.get(opts, :namespace, "/")
    no_mangle = Keyword.get(opts, :no_mangle, false)

    Rclex.Node.get_publishers_info_by_topic(
      name,
      namespace,
      topic_name,
      no_mangle
    )
  end

  @doc """
  Return a list of service names and their types.

  ### opts

  - #{@namespace_doc}

  ## Examples

      iex> Rclex.get_service_names_and_types("node", namespace: "/example")
      [{"/set_test_bool", ["std_srvs/srv/SetBool"]}]
  """
  @spec get_service_names_and_types(
          name :: String.t(),
          opts :: [namespace: String.t()]
        ) :: list()
  def get_service_names_and_types(name, opts \\ []) do
    namespace = Keyword.get(opts, :namespace, "/")
    Rclex.Node.get_service_names_and_types(name, namespace)
  end

  @doc """
  Return a list of service names and types associated with a node.

  ### opts

  - #{@namespace_doc}

  ## Examples

      iex> Rclex.get_service_names_and_types_by_node("node", "example_node", "/example", namespace: "/example")
      [{"/set_test_bool", ["std_srvs/srv/SetBool"]}]
  """
  @spec get_service_names_and_types_by_node(
          name :: String.t(),
          node_name :: String.t(),
          node_namespace :: String.t(),
          opts :: [namespace: String.t()]
        ) :: list()
  def get_service_names_and_types_by_node(name, node_name, node_namespace, opts \\ []) do
    namespace = Keyword.get(opts, :namespace, "/")
    Rclex.Node.get_service_names_and_types_by_node(name, namespace, node_name, node_namespace)
  end

  @doc """
  Return a list of topic names and types for subscriptions associated with a node.

  ### opts

  - #{@namespace_doc}
  - #{@no_demangle_doc}

  ## Examples

      iex> Rclex.get_subscriber_names_and_types_by_node("node", "node", "/example", namespace: "/example")
      [{"/chatter", ["std_msgs/msg/String"]}]
  """
  @spec get_subscriber_names_and_types_by_node(
          name :: String.t(),
          node_name :: String.t(),
          node_namespace :: String.t(),
          opts :: [namespace: String.t(), no_demangle: boolean()]
        ) :: [{String.t(), [String.t()]}] | {:error, :not_found}
  def get_subscriber_names_and_types_by_node(name, node_name, node_namespace, opts \\ []) do
    namespace = Keyword.get(opts, :namespace, "/")
    no_demangle = Keyword.get(opts, :no_demangle, false)

    Rclex.Node.get_subscriber_names_and_types_by_node(
      name,
      namespace,
      node_name,
      node_namespace,
      no_demangle
    )
  end

  @doc """
  Return a list of all subscribers to a topic.

  ### opts

  - #{@namespace_doc}
  - #{@no_mangle_doc}

  ## Examples

      iex> Rclex.get_subscribers_info_by_topic("node", "/chatter", "/example")
      [
              %{
                node_name: "node",
                node_namespace: "/example",
                topic_type: "std_msgs/msg/String",
                endpoint_type: 1,
                endpoint_gid: ...,
                qos_profile: ...
              }
      ]
  """
  @spec get_subscribers_info_by_topic(
          name :: String.t(),
          topic_name :: topic_name(),
          opts :: [namespace: String.t(), no_mangle: boolean()]
        ) :: list()
  def get_subscribers_info_by_topic(name, topic_name, opts \\ []) do
    namespace = Keyword.get(opts, :namespace, "/")
    no_mangle = Keyword.get(opts, :no_mangle, false)

    Rclex.Node.get_subscribers_info_by_topic(
      name,
      namespace,
      topic_name,
      no_mangle
    )
  end

  @doc """
  Return a list of topic names and their types.

  ### opts

  - #{@namespace_doc}
  - #{@no_demangle_doc}

  ## Examples

      iex> Rclex.get_subscriber_names_and_types_by_node("node", "node", "/example", namespace: "/example")
      [{"/chatter", ["std_msgs/msg/String"]}]
  """
  @spec get_topic_names_and_types(
          name :: String.t(),
          opts :: [namespace: String.t(), no_demangle: boolean()]
        ) :: [{String.t(), [String.t()]}]
  def get_topic_names_and_types(name, opts \\ []) do
    namespace = Keyword.get(opts, :namespace, "/")
    no_demangle = Keyword.get(opts, :no_demangle, false)
    Rclex.Node.get_topic_names_and_types(name, namespace, no_demangle)
  end

  @doc """
    Check if a service server is available for the given service client.
    This function will return true, if there is a service server available for the given client.

    - #{@service_name_doc}

    ### opts

    - #{@namespace_doc}

    ## Examples

    iex> Rclex.is_service_server_available?("node", "/set_bool", namespace: "/example")
    :false
  """
  @spec is_service_server_available?(
          name :: String.t(),
          service_type :: module(),
          service_name :: service_name(),
          opts :: [namespace: String.t()]
        ) :: boolean
  def service_server_available?(service_type, service_name, name, opts \\ []) do
    namespace = Keyword.get(opts, :namespace, "/")
    Rclex.Client.service_server_available?(service_type, service_name, name, namespace)
  end
end
