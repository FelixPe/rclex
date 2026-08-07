defmodule Rclex do
  alias Rclex.QoS

  @moduledoc """
  User API for `#{__MODULE__}`.
  """

  @namespace_doc "`:namespace` must lead with \"/\". if not specified, the default is \"/\""
  @clock_type_doc "`:clock_type` can be `:system_time`, `:ros_time` or `:steady_time` If not specified, it becomes `:steady_time`."
  @qos_doc "`:qos` if not specified, applied the default, which equals return of `Rclex.QoS.profile_default/0`"
  @qos_goal_service_doc "`:goal_service_qos` if not specified, applied the default, which equals return of `Rclex.QoS.profile_services_default/0`"
  @qos_result_service_doc "`:result_service_qos` if not specified, applied the default, which equals return of `Rclex.QoS.profile_services_default/0`"
  @qos_cancel_service_doc "`:cancel_service_qos` if not specified, applied the default, which equals return of `Rclex.QoS.profile_services_default/0`"
  @qos_feedback_topic_doc "`:feedback_topic_qos` if not specified, applied the default, which equals return of `Rclex.QoS.profile_default/0`"
  @qos_status_topic_doc "`:status_topic_qos` if not specified, applied the default, which equals return of `Rclex.QoS.profile_status_default/0`"

  @topic_name_doc "`topic_name` must lead with \"/\". See all [constraints](https://design.ros2.org/articles/topic_and_service_names.html#ros-2-topic-and-service-name-constraints)"
  @service_name_doc "`service_name` must lead with \"/\". See all [constraints](https://design.ros2.org/articles/topic_and_service_names.html#ros-2-topic-and-service-name-constraints)"
  @action_name_doc "`action_name` must lead with \"/\". See all [constraints](https://design.ros2.org/articles/topic_and_service_names.html#ros-2-topic-and-service-name-constraints)"
  @no_demangle_doc "`:no_demangle` if `true`, return all topics without any demangling. if not specified, the default is `false`"
  @no_mangle_doc "`:no_mangle` if `true`, `topic_name` needs to be a valid middleware topic name, otherwise it should be a valid ROS topic name. if not specified, the default is `false`"
  @goal_uuid_doc "`goal_uuid` define the UUID of the goal. By default a random UUID will be generated."

  @typedoc "#{@topic_name_doc}."
  @type topic_name :: String.t()

  @typedoc "#{@service_name_doc}."
  @type service_name :: String.t()

  @typedoc "#{@action_name_doc}."
  @type action_name :: String.t()

  @typedoc "#{@goal_uuid_doc}."
  @type goal_uuid :: <<_::16, _::_*8>>

  @typedoc "Goal identifier message, with a goal id and time stamp."
  @type goal_info :: %{
          :__struct__ => Rclex.Pkgs.ActionMsgs.Msg.GoalInfo,
          optional(atom()) => any()
        }

  @typedoc "ROS2 message type to communicate a parameter's descriptor"
  @type parameter_descriptor_struct :: %{}

  @typedoc "ROS2 parameter message shape used in parameter event payloads."
  @type parameter_event_parameter :: %{
          :__struct__ => Rclex.Pkgs.RclInterfaces.Msg.Parameter,
          :name => String.t(),
          optional(atom()) => any()
        }

  @typedoc "ROS2 parameter event message shape delivered to parameter event callbacks."
  @type parameter_event :: %{
          :__struct__ => Rclex.Pkgs.RclInterfaces.Msg.ParameterEvent,
          :node => String.t(),
          :new_parameters => [parameter_event_parameter()],
          :changed_parameters => [parameter_event_parameter()],
          :deleted_parameters => [parameter_event_parameter()],
          optional(atom()) => any()
        }

  @doc """
  Start a ROS node. The name of the node must not be `nil` and cannot coincide with another node of the same name.
  Node names must follow these rules:
  - must not be an empty string
  - must only contain alphanumeric characters and underscores (a-z|A-Z|0-9|_)
  - must not start with a number

  ### opts

  - #{@namespace_doc}
  - `:graph_change_callback` is called on every change of the ROS2 graph. The callback function is expected to have zero parameters. To gain insight into the ROS2 graph, use the [graph access functions](#graph).
  - `:remappings` remaps topic/service/action names for this node. Entries must be `{source, target}` tuples.
  - `:ros_args` additional ROS-specific CLI arguments for this node.

  ### Examples

      iex> Rclex.start_node("node", namespace: "/example")
      :ok
      iex> Rclex.start_node("node", namespace: "/example")
      {:error, :already_started}
  """
  @doc section: :node
  @spec start_node(
          name :: String.t(),
          opts :: [
            namespace: String.t(),
            graph_change_callback: function(),
            remappings: [{String.t(), String.t()}],
            ros_args: [String.t()]
          ]
        ) ::
          :ok | {:error, :already_started} | {:error, term()}
  def start_node(name, opts \\ []) when is_binary(name) and is_list(opts) do
    context = Rclex.Context.get()
    namespace = Keyword.get(opts, :namespace, "/")
    graph_change_callback = Keyword.get(opts, :graph_change_callback)
    ros_args = Rclex.RosArgs.node_ros_args(opts)

    case Rclex.NodesSupervisor.start_child(
           context,
           name,
           namespace,
           graph_change_callback,
           ros_args
         ) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> {:error, :already_started}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Stop a ROS node. And also stop the entities on the node, `publisher`, `subscription`, `service`, `client` and `timer`.

  ### opts

  - #{@namespace_doc}

  ### Examples

      iex> Rclex.stop_node("node", namespace: "/example")
      :ok
      iex> Rclex.stop_node("node", namespace: "/example")
      {:error, :not_found}
  """
  @doc section: :node
  @spec stop_node(name :: String.t(), opts :: [namespace: String.t()]) ::
          :ok | {:error, :not_found}
  def stop_node(name, opts \\ []) when is_binary(name) and is_list(opts) do
    namespace = Keyword.get(opts, :namespace, "/")
    Rclex.NodesSupervisor.terminate_child(name, namespace)
  end

  @doc """
  Start a [managed (lifecycle) node](https://design.ros.org/articles/node_lifecycle.html).

  `impl_module` must be a module that `use Rclex.LifecycleNode`. The node and
  the five standard lifecycle services are started immediately; the node
  begins in the `:unconfigured` primary state.

  ### opts

  - `:namespace` — the node namespace, defaults to `"/"`.
  - `:user_state` — initial user state passed to the first lifecycle
    callback, defaults to `%{}`.

  ### Examples

      iex> defmodule MyManaged do
      ...>   use Rclex.LifecycleNode
      ...> end
      iex> Rclex.start_lifecycle_node(MyManaged, "managed", namespace: "/example")
      :ok
      iex> Rclex.lifecycle_get_state("managed", namespace: "/example")
      :unconfigured
      iex> Rclex.lifecycle_change_state("managed", :configure, namespace: "/example")
      :ok
      iex> Rclex.lifecycle_get_state("managed", namespace: "/example")
      :inactive
  """
  @doc section: :lifecycle_node
  @spec start_lifecycle_node(
          impl_module :: module(),
          node_name :: String.t(),
          opts :: [namespace: String.t(), user_state: any()]
        ) :: :ok | {:error, :already_started} | {:error, term()}
  def start_lifecycle_node(impl_module, node_name, opts \\ [])
      when is_atom(impl_module) and is_binary(node_name) and is_list(opts) do
    args =
      Keyword.merge(opts, node_name: node_name, impl_module: impl_module)

    case Rclex.LifecycleNode.start_link(args) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> {:error, :already_started}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Stop a managed node started with `start_lifecycle_node/3`."
  @doc section: :lifecycle_node
  @spec stop_lifecycle_node(node_name :: String.t(), opts :: [namespace: String.t()]) ::
          :ok | {:error, :not_found}
  def stop_lifecycle_node(node_name, opts \\ []) when is_binary(node_name) and is_list(opts) do
    namespace = Keyword.get(opts, :namespace, "/")
    name = Rclex.LifecycleNode.name(node_name, namespace)

    case GenServer.whereis(name) do
      nil -> {:error, :not_found}
      pid -> GenServer.stop(pid)
    end
  end

  @doc "Trigger a lifecycle transition. See `Rclex.LifecycleNode.change_state/3`."
  @doc section: :lifecycle_node
  @spec lifecycle_change_state(
          node_name :: String.t(),
          transition :: Rclex.LifecycleNode.transition(),
          opts :: [namespace: String.t()]
        ) :: :ok | {:error, term()}
  def lifecycle_change_state(node_name, transition, opts \\ []) do
    Rclex.LifecycleNode.change_state(node_name, transition, opts)
  end

  @doc "Return the current primary state of a managed node."
  @doc section: :lifecycle_node
  @spec lifecycle_get_state(node_name :: String.t(), opts :: [namespace: String.t()]) ::
          Rclex.LifecycleNode.primary_state()
  def lifecycle_get_state(node_name, opts \\ []) do
    Rclex.LifecycleNode.get_state(node_name, opts)
  end

  @doc """
  Start a ROS publisher. fter calling this function for a `topic_name`, the node can be used to publish messages of the given type to the given topic using `publish/4`. The message type module can to be generated from .msg files by calling `mix rclex.gen.msgs`, after adding the type to `config :rclex, ros2_message_types`.

  - #{@topic_name_doc}

  ### Examples

      iex> alias Rclex.Pkgs.StdMsgs
      iex> Rclex.start_publisher(StdMsgs.Msg.String, "/chatter", "node", namespace: "/example")
      :ok
      iex> Rclex.start_publisher(StdMsgs.Msg.String, "/chatter", "node", namespace: "/example")
      {:error, :already_started}
  """
  @doc section: :publisher
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
    qos = Keyword.get(opts, :qos, QoS.profile_default())

    case Rclex.Node.start_publisher(message_type, topic_name, node_name, namespace, qos) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> {:error, :already_started}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Stop a ROS publisher. After calling, the node will no longer be advertising that it
  is publishing on this topic (assuming this is the only publisher on this topic) and
  calls to `publish/4` will fail when using this publisher.

  - #{@topic_name_doc}

  ### opts

  - #{@namespace_doc}

  ### Examples

      iex> alias Rclex.Pkgs.StdMsgs
      iex> Rclex.stop_publisher(StdMsgs.Msg.String, "/chatter", "node", namespace: "/example")
      :ok
      iex> Rclex.stop_publisher(StdMsgs.Msg.String, "/chatter", "node", namespace: "/example")
      {:error, :not_found}
  """
  @doc section: :publisher
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
  Publish a ROS message on a topic using a publisher.

  - #{@topic_name_doc}

  ### opts

  - #{@namespace_doc}

  ### Examples

      iex> alias Rclex.Pkgs.StdMsgs
      iex> Rclex.publish(struct(StdMsgs.Msg.String, %{data: "hello"}), "/chatter", "node", namespace: "/example")
      :ok
      iex> Rclex.publish(struct(StdMsgs.Msg.String, %{data: "hello"}), "/chatter", "node")
      {:error, :not_found}
  """
  @doc section: :publisher
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
  Start a ROS subscription. After calling this function, the callback is called for new messages
  of the given `message_type` to the given `topic_name`. The given `node_name` must be valid and
  the resulting subscription is only valid as long as the given node remains valid.
  The message type module can to be generated from .msg files by calling `mix rclex.gen.msgs`,
  after adding the type to `config :rclex, ros2_message_types`.

  The callback may take **1** argument (the message struct) or **2** arguments
  (the message struct and a `MessageInfo` map containing
  `:source_timestamp`, `:received_timestamp`, `:publication_sequence_number`,
  `:reception_sequence_number`, `:publisher_gid`, `:from_intra_process`).

  - #{@topic_name_doc}

  ### opts

  - #{@namespace_doc}
  - #{@qos_doc}

  ### Examples

      iex> alias Rclex.Pkgs.StdMsgs
      iex> Rclex.start_subscription(&IO.inspect/1, StdMsgs.Msg.String, "/chatter", "node", namespace: "/example")
      :ok
      iex> Rclex.start_subscription(&IO.inspect/1, StdMsgs.Msg.String, "/chatter", "node", namespace: "/example")
      {:error, :already_started}

      # 2-arity callback receives MessageInfo
      iex> alias Rclex.Pkgs.StdMsgs
      iex> Rclex.start_subscription(fn _msg, _info -> :ok end, StdMsgs.Msg.String, "/chatter2", "node", namespace: "/example")
      :ok
  """
  @doc section: :subscription
  @spec start_subscription(
          callback :: function(),
          message_type :: module(),
          topic_name :: topic_name(),
          node_name :: String.t(),
          opts :: [namespace: String.t(), qos: QoS.t()]
        ) ::
          :ok | {:error, :already_started} | {:error, term()}
  def start_subscription(callback, message_type, topic_name, node_name, opts \\ [])
      when is_function(callback) and is_atom(message_type) and is_binary(topic_name) and
             is_binary(node_name) and is_list(opts) do
    namespace = Keyword.get(opts, :namespace, "/")
    qos = Keyword.get(opts, :qos, QoS.profile_default())

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
  Stop a ROS subscription. After calling, the node will no longer be subscribed on this topic. However, the given node is still valid.

  - #{@topic_name_doc}

  ### opts

  - #{@namespace_doc}

  ### Examples

      iex> alias Rclex.Pkgs.StdMsgs
      iex> Rclex.stop_subscription(StdMsgs.Msg.String, "/chatter", "node", namespace: "/example")
      :ok
      iex> Rclex.stop_subscription(StdMsgs.Msg.String, "/chatter", "node", namespace: "/example")
      {:error, :not_found}
  """
  @doc section: :subscription
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
  Wait for a single message on `topic_name` and return it.

  Starts a transient subscription, blocks the calling process up to `:timeout`
  milliseconds, then stops the subscription and returns the first message
  received. Useful for one-shot reads (configuration, latched topics, etc.)
  without writing a full subscription callback.

  ### opts

    * `:namespace` — node namespace (default `"/"`).
    * `:qos`       — QoS profile (default `Rclex.QoS.profile_default/0`).
    * `:timeout`   — milliseconds to wait, or `:infinity` (default `5000`).

  ### Examples

      # In another process: Rclex.publish(%StdMsgs.Msg.String{data: "hi"}, "/chatter", "talker")
      iex> Rclex.wait_for_message(StdMsgs.Msg.String, "/chatter", "listener", timeout: 1000)
      {:ok, %Rclex.Pkgs.StdMsgs.Msg.String{data: "hi"}}
  """
  @doc section: :subscription
  @spec wait_for_message(
          message_type :: module(),
          topic_name :: topic_name(),
          node_name :: String.t(),
          opts :: [namespace: String.t(), qos: QoS.t(), timeout: timeout()]
        ) ::
          {:ok, struct()} | {:error, :timeout} | {:error, term()}
  def wait_for_message(message_type, topic_name, node_name, opts \\ [])
      when is_atom(message_type) and is_binary(topic_name) and is_binary(node_name) and
             is_list(opts) do
    namespace = Keyword.get(opts, :namespace, "/")
    qos = Keyword.get(opts, :qos, QoS.profile_default())
    timeout = Keyword.get(opts, :timeout, 5_000)

    me = self()
    ref = make_ref()
    callback = fn msg -> send(me, {ref, msg}) end

    case start_subscription(callback, message_type, topic_name, node_name,
           namespace: namespace,
           qos: qos
         ) do
      :ok ->
        result =
          receive do
            {^ref, msg} -> {:ok, msg}
          after
            timeout -> {:error, :timeout}
          end

        _ = stop_subscription(message_type, topic_name, node_name, namespace: namespace)
        result

      {:error, _reason} = err ->
        err
    end
  end

  @doc """
  Start a ROS service. After calling this function for a ROS service type, the callback is called
  with a parameter of the corresponding request type, expecting a result of the response type
  of the service type. The given `node_name` must be valid and the resulting service is only
  valid as long as the given node remains valid.

  The message type modules for request and response can to be generated by running `mix rclex.gen.msgs`,
  after adding the service type to `config :rclex, ros2_service_types`. The service type is generated by
  running `mix rclex.gen.srvs`.

  - #{@service_name_doc}

  ### opts

  - #{@namespace_doc}
  - #{@qos_doc}

  ### Examples

      iex> alias Rclex.Pkgs.StdSrvs
      iex> Rclex.start_service(fn _ -> %StdSrvs.Srv.SetBool.Response{success: true} end, StdSrvs.Srv.SetBool, "/set_bool", "node", namespace: "/example")
      :ok
      iex> Rclex.start_service(fn _ -> %StdSrvs.Srv.SetBool.Response{success: true} end, StdSrvs.Srv.SetBool, "/set_bool", "node", namespace: "/example")
      {:error, :already_started}
  """
  @doc section: :service
  @spec start_service(
          callback :: function(),
          service_type :: module(),
          service_name :: service_name(),
          node_name :: String.t(),
          opts :: [namespace: String.t(), qos: QoS.t()]
        ) ::
          :ok | {:error, :already_started} | {:error, term()}
  def start_service(callback, service_type, service_name, node_name, opts \\ [])
      when is_function(callback) and is_atom(service_type) and is_binary(service_name) and
             is_binary(node_name) and is_list(opts) do
    namespace = Keyword.get(opts, :namespace, "/")
    qos = Keyword.get(opts, :qos, QoS.profile_services_default())

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
  Stop a ROS service. After calling, the node will no longer listen for requests for this service.

  - #{@service_name_doc}

  ### opts

  - #{@namespace_doc}

  ### Examples

      iex> alias Rclex.Pkgs.StdSrvs
      iex> Rclex.stop_service(StdSrvs.Srvg.SetBool, "/set_bool", "node", namespace: "/example")
      :ok
      iex> Rclex.stop_service(StdSrvs.Srvg.SetBool, "/does_not_exist", "node", namespace: "/example")
      {:error, :not_found}
  """
  @doc section: :service
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
  Start a ROS client. After calling this function for a ROS `service_type`, it can be used to
  send requests of the given type to the service server. If the request is received by
  a (possibly remote) service and if the service sends a response,
  the callback with a response of the service response type is called.
  The given `node_name` must be valid and the resulting client is only valid as long as the given node remains valid.

  The message type modules for request and response can to be generated by running `mix rclex.gen.msgs`,
  after adding the service type to `config :rclex, ros2_service_types`. The service type is generated by
  running `mix rclex.gen.srvs`.

  - #{@service_name_doc}

  ### opts

  - #{@namespace_doc}
  - #{@qos_doc}

  ### Examples

      iex> alias Rclex.Pkgs.StdSrvs
      iex> callback = fn _request, _response -> nil end
      iex> Rclex.start_client(callback, StdSrvs.Srv.SetBool, "/set_test_bool", "name")
      :ok
      iex> Rclex.start_client(callback, StdSrvs.Srv.SetBool, "/set_test_bool", "name")
      {:error, :already_started}
      iex> Rclex.call_async(%StdSrvs.Srv.SetBool.Request{data: true}, "/set_bool", "node", namespace: "/example")
      :ok
  """
  @doc section: :client
  @spec start_client(
          callback :: function(),
          service_type :: module(),
          service_name :: service_name(),
          node_name :: String.t(),
          opts :: [namespace: String.t(), qos: QoS.t()]
        ) ::
          :ok | {:error, :already_started} | {:error, term()}
  def start_client(callback, service_type, service_name, node_name, opts \\ [])
      when is_function(callback) and is_atom(service_type) and is_binary(service_name) and
             is_binary(node_name) and is_list(opts) do
    namespace = Keyword.get(opts, :namespace, "/")
    qos = Keyword.get(opts, :qos, QoS.profile_services_default())

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
  Call a ROS service asynchronously using an initialized client. The callback of the client is called with the returned response.

  - #{@service_name_doc}

  ### opts

  - #{@namespace_doc}

  ### Examples

      iex> alias Rclex.Pkgs.StdSrvs
      iex> Rclex.call_async(%StdSrvs.Srv.SetBoolRequest{data: true}, "/set_bool", "node", namespace: "/example")
      :ok
  """
  @doc section: :client
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
  Perform a blocking service call with a timeout measured in seconds.

  The function returns `{:ok, response}` if the response is received within
  the specified interval or `{:error, :timeout}` if the timeout elapses first.
  If `timeout_sec` is `nil`, the call will wait indefinitely.  The `timeout_sec`
  argument is a float number of seconds.

  - #{@service_name_doc}

  ### opts

  - #{@namespace_doc}

  ### Examples

      iex> alias Rclex.Pkgs.StdSrvs
      iex> Rclex.call_timeout(%StdSrvs.Srv.SetBool.Request{data: true}, "/set_bool", "node", 1.0, namespace: "/example")
      {:ok, %StdSrvs.Srv.SetBool.Response{data: false}}
  """
  @doc section: :client
  @spec call_timeout(
          request :: struct(),
          service_name :: service_name(),
          node_name :: String.t(),
          timeout_sec :: float() | nil,
          opts :: [namespace: String.t()]
        ) ::
          {:ok, struct()} | {:error, :timeout} | {:error, :not_found} | {:error, term()}
  def call_timeout(request, service_name, node_name, timeout_sec, opts \\ [])
      when is_binary(service_name) and is_binary(node_name) and is_list(opts) do
    namespace = Keyword.get(opts, :namespace, "/")

    Rclex.Client.call_timeout(
      request,
      service_name,
      node_name,
      namespace,
      timeout_sec
    )
  end

  @doc """
  Stop ROS client. After calling this function, calls `call_async/4` will with `{:error, :not_found}` when using this client. However, the given node is still valid.

  - #{@service_name_doc}

  ### opts

  - #{@namespace_doc}

  ### Examples

      iex> alias Rclex.Pkgs.StdSrvs
      iex> Rclex.stop_client(StdSrvs.Srvg.SetBool, "/set_bool", "node", namespace: "/example")
      :ok
      iex> Rclex.stop_client(StdSrvs.Srvg.SetBool, "/does_not_exist", "node", namespace: "/example")
      {:error, :not_found}
  """
  @doc section: :client
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
  Start a ROS action server. After calling this function for a ROS action type, it's listening for action goals. The given `node_name` must be valid and the resulting action server is only
  valid as long as the given node remains valid.

  The message type modules for all requests and responses of the action type can to be generated by running `mix rclex.gen.msgs`,
  after adding the action type to `config :rclex, ros2_action_types`. The action type is generated by
  running `mix rclex.gen.action`.

  - #{@action_name_doc}
  - The purpose of the `execute_callback` is to execute the action goal and return a result when finished. The callback should take two parameter. The first parameter is containing the goal request as a struct. The second parameter is the `feedback_publish` callback, that expects one parameter of the feedback type and can be used to send feedback to action clients. The `execute_callback` must return a result struct for the action type.

  ### opts

  - #{@namespace_doc}
  - The purpose of the `cancel_callback` is to decide if a request to cancel an on-going (or queued) goal should be accepted or rejected. The callback should take one parameter containing the goal handle and must return the atom `:accept` or `:reject`. By default all cancel requests are rejected.
  - The purpose of the `goal_callback` is to decide if a new goal should be accepted or rejected. The callback should take the goal struct as a parameter and must return the atom `:accept` or `:reject`. By default all goals are accepted.
  - The `handle_accepted_callback` function is called whenever a new goal has been accepted by this action server. The function should expect as arguments: goal info, action_type, action name, node name and namespace.
  - options
    - #{@qos_goal_service_doc}
    - #{@qos_result_service_doc}
    - #{@qos_cancel_service_doc}
    - #{@qos_feedback_topic_doc}
    - #{@qos_status_topic_doc}
    - #{@clock_type_doc}
    - `:result_timeout`, defines how long the result for a goal will be available after execution. If not defined, it is 10.0 seconds.

  ### Examples

      iex> alias Rclex.Pkgs.Tf2Msgs.Action
      iex> Rclex.start_action_server(execute_callback, Action.LookupTransform, "/lookup_transform", "node", namespace: "/example", goal_callback: goal_callback, handle_accepted_callback: handle_accepted_callback, cancel_callback: cancel_callback)
      :ok
      iex> Rclex.start_action_server(execute_callback, Action.LookupTransform, "/lookup_transform", "node", namespace: "/example", goal_callback: goal_callback, handle_accepted_callback: handle_accepted_callback, cancel_callback: cancel_callback)
      {:error, :already_started}
  """
  @doc section: :action_server
  @spec start_action_server(
          execute_callback :: function(),
          action_type :: module(),
          action_name :: action_name(),
          node_name :: String.t(),
          opts :: [
            namespace: String.t(),
            options: Rclex.ActionServerOptions.t(),
            goal_callback: function(),
            handle_accepted_callback: function(),
            cancel_callback: function()
          ]
        ) :: :ok | {:error, :already_started} | {:error, term()}
  def start_action_server(
        execute_callback,
        action_type,
        action_name,
        node_name,
        opts \\ []
      )
      when is_function(execute_callback) and is_atom(action_type) and is_binary(action_name) and
             is_binary(node_name) and is_list(opts) do
    namespace = Keyword.get(opts, :namespace, "/")
    options = Keyword.get(opts, :options, Rclex.ActionServerOptions.default())
    goal_callback = Keyword.get(opts, :goal_callback, fn _goal -> :accept end)
    cancel_callback = Keyword.get(opts, :cancel_callback, fn _goal -> :reject end)

    handle_accepted_callback =
      Keyword.get(opts, :handle_accepted_callback, fn goal_info_struct,
                                                      action_type,
                                                      action_name,
                                                      name,
                                                      namespace ->
        Rclex.execute_goal(
          goal_info_struct,
          action_type,
          action_name,
          name,
          namespace: namespace
        )
      end)

    case Rclex.Node.start_action_server(
           {execute_callback, goal_callback, handle_accepted_callback, cancel_callback},
           action_type,
           action_name,
           node_name,
           namespace,
           options
         ) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> {:error, :already_started}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Execute accepted goal on a ROS action server. After calling, the execution of the `execute_callback` will be started.
  This function will by default be called in the `handle_accepted_callback`.

  - #{@action_name_doc}

  ### opts

  - #{@namespace_doc}

  ### Examples

      iex> alias Rclex.Pkgs.Tf2Msgs.Action
      iex> handle_accepted_callback = fn goal_info_struct, action_type, action_name, name, namespace -> Rclex.execute_goal(goal_info_struct, action_type, action_name, name, namespace: namespace) end
      end
      iex> Rclex.start_action_server(execute_callback, Action.LookupTransform, "/lookup_transform", "node", namespace: "/example", goal_callback: goal_callback, handle_accepted_callback: handle_accepted_callback, cancel_callback: cancel_callback)
      :ok
      iex> Rclex.stop_action_server(Action.LookupTransform, "/lookup_transform", "node", namespace: "/example")
      :ok

  """
  @doc section: :action_server
  @spec execute_goal(
          goal_info :: goal_info(),
          action_type :: module(),
          action_name :: action_name(),
          node_name :: String.t(),
          opts :: [namespace: String.t()]
        ) ::
          :ok | {:error, :not_found}
  def execute_goal(goal_info, action_type, action_name, node_name, opts \\ [])
      when is_atom(action_type) and is_binary(action_name) and is_binary(node_name) and
             is_list(opts) do
    namespace = Keyword.get(opts, :namespace, "/")
    Rclex.ActionServer.execute_goal(goal_info, action_type, action_name, node_name, namespace)
  end

  @doc """
  Stop a ROS action server. After calling, the node will no longer listen for goals for this server.

  - #{@action_name_doc}

  ### opts

  - #{@namespace_doc}

  ### Examples

      iex> alias Rclex.Pkgs.Tf2Msgs.Action
      iex> Rclex.stop_action_server(Action.LookupTransform, "/lookup_transform", "node", namespace: "/example")
      :ok
      iex> Rclex.stop_action_server(Action.LookupTransform, "/does_not_exist", "node", namespace: "/example")
      {:error, :not_found}
  """
  @doc section: :action_server
  @spec stop_action_server(
          action_type :: module(),
          action_name :: action_name(),
          node_name :: String.t(),
          opts :: [namespace: String.t()]
        ) ::
          :ok | {:error, :not_found}
  def stop_action_server(action_type, action_name, node_name, opts \\ [])
      when is_atom(action_type) and is_binary(action_name) and is_binary(node_name) and
             is_list(opts) do
    namespace = Keyword.get(opts, :namespace, "/")
    Rclex.Node.stop_action_server(action_type, action_name, node_name, namespace)
  end

  @doc """
  Start a ROS action client. After calling this function for a ROS action type, goals can be set for the action server. The given `node_name` must be valid and the resulting action client is only
  valid as long as the given node remains valid.

  The message type modules for all requests and responses of the action type can to be generated by running `mix rclex.gen.msgs`,
  after adding the action type to `config :rclex, ros2_action_types`. The action type is generated by
  running `mix rclex.gen.action`.

  - #{@action_name_doc}

  ### opts

  - #{@namespace_doc}
  - options
    - #{@qos_goal_service_doc}
    - #{@qos_result_service_doc}
    - #{@qos_cancel_service_doc}
    - #{@qos_feedback_topic_doc}
    - #{@qos_status_topic_doc}

  ### Examples

      iex> alias Rclex.Pkgs.Tf2Msgs.Action
      iex> Rclex.start_action_client(Action.LookupTransform, "/lookup_transform", "node", namespace: "/example")
      :ok
      iex> Rclex.start_action_client(Action.LookupTransform, "/lookup_transform", "node", namespace: "/example")
      {:error, :already_started}
  """
  @doc section: :action_client
  @spec start_action_client(
          action_type :: module(),
          action_name :: service_name(),
          node_name :: String.t(),
          opts :: [
            namespace: String.t(),
            options: Rclex.ActionClientOptions.t()
          ]
        ) :: :ok | {:error, :already_started} | {:error, term()}
  def start_action_client(
        action_type,
        action_name,
        node_name,
        opts \\ []
      )
      when is_atom(action_type) and is_binary(action_name) and is_binary(node_name) and
             is_list(opts) do
    namespace = Keyword.get(opts, :namespace, "/")
    options = Keyword.get(opts, :options, Rclex.ActionClientOptions.default())

    case Rclex.Node.start_action_client(
           action_type,
           action_name,
           node_name,
           namespace,
           options
         ) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> {:error, :already_started}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Stop a ROS action client. After calling, the node will no longer be able to communicate with the action server.

  - #{@action_name_doc}

  ### opts

  - #{@namespace_doc}

  ### Examples

      iex> alias Rclex.Pkgs.Tf2Msgs.Action
      iex> Rclex.stop_action_client(Action.LookupTransform, "/lookup_transform", "node", namespace: "/example")
      :ok
      iex> Rclex.stop_action_client(Action.LookupTransform, "/does_not_exist", "node", namespace: "/example")
      {:error, :not_found}
  """
  @doc section: :action_client
  @spec stop_action_client(
          action_type :: module(),
          action_name :: action_name(),
          node_name :: String.t(),
          opts :: [namespace: String.t()]
        ) ::
          :ok | {:error, :not_found}
  def stop_action_client(action_type, action_name, node_name, opts \\ [])
      when is_atom(action_type) and is_binary(action_name) and is_binary(node_name) and
             is_list(opts) do
    namespace = Keyword.get(opts, :namespace, "/")
    Rclex.Node.stop_action_client(action_type, action_name, node_name, namespace)
  end

  @doc """
  Send an action goal to a ROS action server asynchronously using an initialized action client. The callback is called with the returned response.

  - #{@action_name_doc}

  ### opts

  - #{@namespace_doc}
  - The function, defined by `:feedback_callback`, gets called, whenever new feedback is available for the action goal. The callback function needs to have a arity of 1, with a feedback struct of the action type as it's only parameter.
  - The function, defined by `:accepted_callback`, gets called, when the action server responded to the sent goal request. The callback function need to expect 3 parameters: uuid as binary, accepted as bool and timestamp as `Rclex.Pkgs.BuiltinInterfaces.Msg.Time`.
  - #{@goal_uuid_doc}

  ### Examples

      iex> alias Rclex.Pkgs.Tf2Msgs.Action
      iex> {:ok, uuid} = Rclex.send_goal_async(%Action.LookupTransform.Goal{theta: 0.123}, "/lookup_transform", "node", namespace: "/example")
  """
  @doc section: :action_client
  @spec send_goal_async(
          goal :: struct(),
          action_name :: action_name(),
          node_name :: String.t(),
          opts :: [
            namespace: String.t(),
            feedback_callback: function(),
            accepted_callback: function(),
            goal_uuid: goal_uuid()
          ]
        ) ::
          :ok | {:error, :not_found} | {:error, term()}
  def send_goal_async(goal, action_name, node_name, opts \\ [])
      when is_binary(action_name) and
             is_binary(node_name) and is_list(opts) do
    namespace = Keyword.get(opts, :namespace, "/")
    goal_uuid = Keyword.get(opts, :goal_uuid, Rclex.ActionHelpers.gen_uuid())
    feedback_callback = Keyword.get(opts, :feedback_callback, fn _feedback -> nil end)

    accepted_callback =
      Keyword.get(opts, :accepted_callback, fn _uuid, _accepted, _timestamp -> nil end)

    Rclex.ActionClient.send_goal_async(
      goal,
      goal_uuid,
      feedback_callback,
      accepted_callback,
      action_name,
      node_name,
      namespace
    )
  end

  @doc """
  Request to cancel an action goal on a ROS action server asynchronously using an initialized action client.

  - #{@goal_uuid_doc}
  - The `cancel_callback` is called with the cancel request has been processed, it get return_code and as list of the canceled goals as parameters.
  - #{@action_name_doc}

  ### opts

  - #{@namespace_doc}

  ### Examples

      iex> alias Rclex.Pkgs.Tf2Msgs.Action
      iex> {:ok, uuid} = Rclex.send_goal_async(%Action.LookupTransform.Goal{theta: 0.123}, "/lookup_transform", "node", namespace: "/example")
      iex> Rclex.cancel_goal_async(uuid, cancel_callback, Action.LookupTransform, "/lookup_transform", "node", namespace: "/example")
      :ok
  """
  @doc section: :action_client
  @spec cancel_goal_async(
          goal_uuid :: goal_uuid(),
          cancel_callback :: function(),
          action_type :: atom(),
          action_name :: action_name(),
          node_name :: String.t(),
          opts :: [
            namespace: String.t()
          ]
        ) ::
          :ok | {:error, :not_found} | {:error, term()}
  def cancel_goal_async(
        goal_uuid,
        cancel_callback,
        action_type,
        action_name,
        node_name,
        opts \\ []
      )
      when is_function(cancel_callback) and is_atom(action_type) and is_binary(action_name) and
             is_binary(node_name) and is_list(opts) do
    namespace = Keyword.get(opts, :namespace, "/")

    Rclex.ActionClient.cancel_goal_async(
      goal_uuid,
      cancel_callback,
      action_type,
      action_name,
      node_name,
      namespace
    )
  end

  @doc """
  Request an action goal result from a ROS action server asynchronously using an initialized action client.

  - #{@goal_uuid_doc}
  - The `result_callback` is called with the returned status and result, as soon as it gets available.
  - #{@action_name_doc}

  ### opts

  - #{@namespace_doc}

  ### Examples

      iex> alias Rclex.Pkgs.Tf2Msgs.Action
      iex> {:ok, uuid} = Rclex.send_goal_async(%Action.LookupTransform.Goal{target_frame: "/base_frame"}, "/lookup_transform", "node", namespace: "/example")
      iex> Rclex.get_result_async(uuid, result_callback, Action.LookupTransform, "/lookup_transform", "node", namespace: "/example")
      :ok
  """
  @doc section: :action_client
  @spec get_result_async(
          goal_uuid :: goal_uuid(),
          result_callback :: function(),
          action_type :: atom(),
          action_name :: action_name(),
          node_name :: String.t(),
          opts :: [
            namespace: String.t()
          ]
        ) ::
          :ok | {:error, :not_found} | {:error, term()}
  def get_result_async(
        goal_uuid,
        result_callback,
        action_type,
        action_name,
        node_name,
        opts \\ []
      )
      when is_function(result_callback) and is_atom(action_type) and is_binary(action_name) and
             is_binary(node_name) and is_list(opts) do
    namespace = Keyword.get(opts, :namespace, "/")

    Rclex.ActionClient.get_result_async(
      goal_uuid,
      result_callback,
      action_type,
      action_name,
      node_name,
      namespace
    )
  end

  @doc """
  Check if the action server is available using an initialized action client.

  - #{@action_name_doc}

  ### opts

  - #{@namespace_doc}

  ### Examples

      iex> alias Rclex.Pkgs.Tf2Msgs.Action
      iex> Rclex.send_goal_async(Action.LookupTransform, "/lookup_transform", "node", namespace: "/example")
      :ok
  """
  @doc section: :action_client
  @spec action_server_available?(
          action_type :: module(),
          action_name :: action_name(),
          node_name :: String.t(),
          opts :: [namespace: String.t()]
        ) :: boolean() | {:error, :not_found}
  def action_server_available?(action_type, action_name, node_name, opts \\ [])
      when is_binary(action_name) and
             is_binary(node_name) and is_list(opts) do
    namespace = Keyword.get(opts, :namespace, "/")

    Rclex.ActionClient.action_server_available?(action_type, action_name, node_name, namespace)
  end

  @doc """
  Start a timer. A timer required a period in milliseconds, a callback function, a name and a node. The callback gets called, when the defined period passed.

  ### opts

  - #{@namespace_doc}

  ### Examples

      iex> Rclex.start_timer(1000, fn -> IO.inspect("tick") end, "tick", "node", namespace: "/example")
      :ok
      iex> Rclex.start_timer(1000, fn -> IO.inspect("tick") end, "tick", "node", namespace: "/example")
      {:error, :already_started}
  """
  @doc section: :time
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
  Stop a timer. This function will deallocate any memory and make the timer invalid. For a timer that is already invalid, `{:error, :not_found}` is returned.

  ### opts

  - #{@namespace_doc}

  ### Examples

      iex> Rclex.stop_timer("tick", "node", namespace: "/example")
      :ok
      iex> Rclex.stop_timer("tick", "node", namespace: "/example")
      {:error, :not_found}
  """
  @doc section: :time
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
  Start a `Rclex.Clock` GenServer.

  The clock can be looked up by its registered name (default `Rclex.Clock`)
  and queried via `Rclex.Clock.now/1` or the `now/1` helper below.

  ### opts

    * `:clock_type` — `:system_time` (default), `:steady_time`, or `:ros_time`.
    * `:name`       — registered name (default `Rclex.Clock`).

  ### Examples

      iex> Rclex.start_clock(clock_type: :steady_time, name: :steady)
      :ok
      iex> %Rclex.Time{clock_type: :steady_time} = Rclex.now(:steady)
      iex> Rclex.stop_clock(:steady)
      :ok
  """
  @doc section: :clock
  @spec start_clock(opts :: [clock_type: Rclex.Clock.clock_type(), name: GenServer.name()]) ::
          :ok | {:error, :already_started} | {:error, term()}
  def start_clock(opts \\ []) when is_list(opts) do
    case Rclex.Clock.start_link(opts) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> {:error, :already_started}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Stop a previously started `Rclex.Clock`."
  @doc section: :clock
  @spec stop_clock(GenServer.server()) :: :ok
  def stop_clock(server \\ Rclex.Clock) do
    Rclex.Clock.stop(server)
  end

  @doc "Return the current time of the named clock as a `Rclex.Time`."
  @doc section: :clock
  @spec now(GenServer.server()) :: Rclex.Time.t()
  def now(server \\ Rclex.Clock) do
    Rclex.Clock.now(server)
  end

  @doc """
  Declare a parameter on a node.

  Parameters must be declared before they can be set or retrieved.
  Optionally, a default value and descriptor can be provided.

  ### opts

  - #{@namespace_doc}

  ### Examples

      iex> Rclex.declare_parameter("node", "my_param", default_value: 42, namespace: "/example")
      :ok
      iex> Rclex.declare_parameter("node", "my_string", default_value: "hello", namespace: "/example")
      :ok
  """
  @doc section: :parameter
  @spec declare_parameter(
          node_name :: String.t(),
          parameter_name :: String.t(),
          opts :: [
            namespace: String.t(),
            type: atom(),
            default_value: any(),
            read_only: boolean(),
            dynamic_typing: boolean(),
            description: String.t(),
            additional_constraints: String.t(),
            floating_point_range: [number()],
            integer_range: [integer()]
          ]
        ) :: :ok | {:error, :already_declared}
  def declare_parameter(node_name, parameter_name, opts \\ [])
      when is_binary(node_name) and is_binary(parameter_name) and is_list(opts) do
    namespace = Keyword.get(opts, :namespace, "/")
    Rclex.ParameterServer.declare_parameter(node_name, namespace, parameter_name, opts)
  end

  @doc """
  Get the value of a parameter.

  Returns the current value of the parameter if it exists and has been declared.

  ### opts

  - #{@namespace_doc}

  ### Examples

      iex> Rclex.get_parameter("node", "my_param", namespace: "/example")
      {:ok, 42}
      iex> Rclex.get_parameter("node", "nonexistent", namespace: "/example")
      {:error, :not_declared}
  """
  @doc section: :parameter
  @spec get_parameter(
          node_name :: String.t(),
          parameter_name :: String.t(),
          opts :: [namespace: String.t()]
        ) :: {:ok, any()} | {:error, :not_declared}
  def get_parameter(node_name, parameter_name, opts \\ [])
      when is_binary(node_name) and is_binary(parameter_name) and is_list(opts) do
    namespace = Keyword.get(opts, :namespace, "/")
    Rclex.ParameterServer.get_parameter(node_name, namespace, parameter_name)
  end

  @doc """
  Set the value of a parameter.

  The parameter must be declared first using `declare_parameter/3`.

  ### opts

  - #{@namespace_doc}

  ### Examples

      iex> Rclex.set_parameter("node", "my_param", 100, namespace: "/example")
      :ok
      iex> Rclex.set_parameter("node", "undeclared", 50, namespace: "/example")
      {:error, :not_declared}
  """
  @doc section: :parameter
  @spec set_parameter(
          node_name :: String.t(),
          parameter_name :: String.t(),
          value :: any(),
          opts :: [namespace: String.t(), type: atom()]
        ) :: :ok | {:error, :not_declared}
  def set_parameter(node_name, parameter_name, value, opts \\ [])
      when is_binary(node_name) and is_binary(parameter_name) and is_list(opts) do
    namespace = Keyword.get(opts, :namespace, "/")
    Rclex.ParameterServer.set_parameter(node_name, namespace, parameter_name, value, opts)
  end

  @doc """
  Set multiple parameters atomically.

  All parameters will be set if all are valid, otherwise none will be set.
  Parameters must be provided as a list of {name, value} tuples.

  ### opts

  - #{@namespace_doc}

  ### Examples

      iex> Rclex.set_parameters("node", [{"param1", 10}, {"param2", "hello"}], namespace: "/example")
      :ok
      iex> Rclex.set_parameters("node", [{"param1", 10}, {"undeclared", 20}], namespace: "/example")
      {:error, {:undeclared_parameters, ["undeclared"]}}
  """
  @doc section: :parameter
  @spec set_parameters(
          node_name :: String.t(),
          parameters :: [{String.t(), any()}],
          opts :: [namespace: String.t()]
        ) :: :ok | {:error, {:undeclared_parameters, [String.t()]}}
  def set_parameters(node_name, parameters, opts \\ [])
      when is_binary(node_name) and is_list(parameters) and is_list(opts) do
    namespace = Keyword.get(opts, :namespace, "/")

    Rclex.ParameterServer.set_parameters(node_name, namespace, parameters, true, true)
  end

  @doc """
  List all declared parameters on a node.

  Returns a list of parameter names that have been declared on the node.

  ### opts

  - #{@namespace_doc}

  ### Examples

      iex> Rclex.list_parameters("node", namespace: "/example")
      ["my_param", "my_string"]
  """
  @doc section: :parameter
  @spec list_parameters(
          node_name :: String.t(),
          opts :: [namespace: String.t()]
        ) :: [String.t()]
  def list_parameters(node_name, opts \\ [])
      when is_binary(node_name) and is_list(opts) do
    namespace = Keyword.get(opts, :namespace, "/")
    Rclex.ParameterServer.list_parameters(node_name, namespace)
  end

  @doc """
  Get parameter descriptors for the specified parameters.

  If no parameter names are provided, returns descriptors for all declared parameters.

  ### opts

  - #{@namespace_doc}

  ### Examples

      iex> Rclex.describe_parameters("node", ["my_param"], namespace: "/example")
      [%Rclex.Pkgs.RclInterfaces.Msg.ParameterDescriptor{name: "my_param", ...}]
      iex> Rclex.describe_parameters("node", namespace: "/example")
      [%Rclex.Pkgs.RclInterfaces.Msg.ParameterDescriptor{...}, ...]
  """
  @doc section: :parameter
  @spec describe_parameters(
          node_name :: String.t(),
          parameter_names :: [String.t()],
          opts :: [namespace: String.t()]
        ) :: [parameter_descriptor_struct]
  def describe_parameters(node_name, parameter_names \\ [], opts \\ [])
      when is_binary(node_name) and is_list(parameter_names) and is_list(opts) do
    namespace = Keyword.get(opts, :namespace, "/")
    Rclex.ParameterServer.describe_parameters(node_name, namespace, parameter_names)
  end

  @doc """
  Get parameter types for the specified parameters.

  Returns a list of parameter types corresponding to the parameter names.

  ### opts

  - #{@namespace_doc}

  ### Examples

      iex> Rclex.get_parameter_types("node", ["my_param", "my_string"], namespace: "/example")
      [:integer, :string]
  """
  @doc section: :parameter
  @spec get_parameter_types(
          node_name :: String.t(),
          parameter_names :: [String.t()],
          opts :: [namespace: String.t()]
        ) :: [atom()]
  def get_parameter_types(node_name, parameter_names, opts \\ [])
      when is_binary(node_name) and is_list(parameter_names) and is_list(opts) do
    namespace = Keyword.get(opts, :namespace, "/")
    Rclex.ParameterServer.get_parameter_types(node_name, namespace, parameter_names)
  end

  @doc """
  Add an on-set parameter callback to a node.

  The callback receives a list of `{parameter_name, parameter_value_struct}` tuples and
  may return `:ok`, `true`, `false`, `{:error, reason}` or a `%SetParametersResult{}`-like
  struct (`%{successful: boolean(), reason: String.t()}`).

  This callback is executed before updates are committed.

  ### opts

  - #{@namespace_doc}

  ### Examples

      iex> callback = fn _params -> :ok end
      iex> Rclex.add_on_set_parameters_callback("node", callback, namespace: "/example")
      :ok
  """
  @doc section: :parameter
  @spec add_on_set_parameters_callback(
          node_name :: String.t(),
          callback :: ([{String.t(), struct()}] -> any()),
          opts :: [namespace: String.t()]
        ) :: :ok
  def add_on_set_parameters_callback(node_name, callback, opts \\ [])
      when is_binary(node_name) and is_function(callback, 1) and is_list(opts) do
    namespace = Keyword.get(opts, :namespace, "/")
    Rclex.ParameterServer.add_on_set_parameters_callback(node_name, namespace, callback)
  end

  @doc """
  Remove an on-set parameter callback from a node.

  ### opts

  - #{@namespace_doc}

  ### Examples

      iex> Rclex.remove_on_set_parameters_callback("node", callback, namespace: "/example")
      :ok
  """
  @doc section: :parameter
  @spec remove_on_set_parameters_callback(
          node_name :: String.t(),
          callback :: ([{String.t(), struct()}] -> any()),
          opts :: [namespace: String.t()]
        ) :: :ok
  def remove_on_set_parameters_callback(node_name, callback, opts \\ [])
      when is_binary(node_name) and is_function(callback, 1) and is_list(opts) do
    namespace = Keyword.get(opts, :namespace, "/")
    Rclex.ParameterServer.remove_on_set_parameters_callback(node_name, namespace, callback)
  end

  @doc """
  Add a pre-set parameter callback to a node.

  The callback receives a list of `{parameter_name, parameter_value_struct}` tuples and may
  return a modified list.

  ### opts

  - #{@namespace_doc}

  ### Examples

      iex> callback = fn parameters -> parameters end
      iex> Rclex.add_pre_set_parameters_callback("node", callback, namespace: "/example")
      :ok
  """
  @doc section: :parameter
  @spec add_pre_set_parameters_callback(
          node_name :: String.t(),
          callback :: ([{String.t(), struct()}] -> [{String.t(), struct()}]),
          opts :: [namespace: String.t()]
        ) :: :ok
  def add_pre_set_parameters_callback(node_name, callback, opts \\ [])
      when is_binary(node_name) and is_function(callback, 1) and is_list(opts) do
    namespace = Keyword.get(opts, :namespace, "/")
    Rclex.ParameterServer.add_pre_set_parameters_callback(node_name, namespace, callback)
  end

  @doc """
  Remove a pre-set parameter callback from a node.

  ### opts

  - #{@namespace_doc}

  ### Examples

      iex> Rclex.remove_pre_set_parameters_callback("node", callback, namespace: "/example")
      :ok
  """
  @doc section: :parameter
  @spec remove_pre_set_parameters_callback(
          node_name :: String.t(),
          callback :: ([{String.t(), struct()}] -> [{String.t(), struct()}]),
          opts :: [namespace: String.t()]
        ) :: :ok
  def remove_pre_set_parameters_callback(node_name, callback, opts \\ [])
      when is_binary(node_name) and is_function(callback, 1) and is_list(opts) do
    namespace = Keyword.get(opts, :namespace, "/")
    Rclex.ParameterServer.remove_pre_set_parameters_callback(node_name, namespace, callback)
  end

  @doc """
  Add a post-set parameter callback to a node.

  The callback function will be invoked whenever any parameter on the node changes.
  The callback receives the parameter name, new value, and old value as arguments.

  ### opts

  - #{@namespace_doc}

  ### Examples

      iex> callback = fn name, new_val, old_val -> IO.puts("#\{name\} changed from #\{old_val\} to #\{new_val\}") end
      iex> Rclex.add_post_set_parameters_callback("node", callback, namespace: "/example")
      :ok
  """
  @doc section: :parameter
  @spec add_post_set_parameters_callback(
          node_name :: String.t(),
          callback :: (String.t(), any(), any() -> any()),
          opts :: [namespace: String.t()]
        ) :: :ok
  def add_post_set_parameters_callback(node_name, callback, opts \\ [])
      when is_binary(node_name) and is_function(callback, 3) and is_list(opts) do
    namespace = Keyword.get(opts, :namespace, "/")
    Rclex.ParameterServer.add_post_set_parameters_callback(node_name, namespace, callback)
  end

  @doc """
  Remove a post-set parameter callback from a node.

  ### opts

  - #{@namespace_doc}

  ### Examples

      iex> Rclex.remove_post_set_parameters_callback("node", callback, namespace: "/example")
      :ok
  """
  @doc section: :parameter
  @spec remove_post_set_parameters_callback(
          node_name :: String.t(),
          callback :: (String.t(), any(), any() -> any()),
          opts :: [namespace: String.t()]
        ) :: :ok
  def remove_post_set_parameters_callback(node_name, callback, opts \\ [])
      when is_binary(node_name) and is_function(callback, 3) and is_list(opts) do
    namespace = Keyword.get(opts, :namespace, "/")
    Rclex.ParameterServer.remove_post_set_parameters_callback(node_name, namespace, callback)
  end

  # ----------------------------------------------------------------------------
  # Parameter client (remote parameter access)
  # ----------------------------------------------------------------------------

  @doc """
  Start a parameter client on the local node `client_node_name` that targets
  the parameter services of the remote node `server_node_name`.

  This registers six service clients on the local node, one for each ROS 2
  parameter service. Use `stop_parameter_client/3` to clean up.

  ### opts

  - #{@namespace_doc} (namespace of the local client node)
  - `:server_namespace` namespace of the remote server node, default `"/"`
  - `:qos` service QoS, defaults to `Rclex.QoS.profile_services_default/0`

  ### Examples

      iex> Rclex.start_parameter_client("server_node", "client_node", server_namespace: "/example")
      :ok
  """
  @doc section: :parameter_client
  @spec start_parameter_client(
          server_node_name :: String.t(),
          client_node_name :: String.t(),
          opts :: [namespace: String.t(), server_namespace: String.t(), qos: QoS.t()]
        ) :: :ok | {:error, term()}
  def start_parameter_client(server_node_name, client_node_name, opts \\ [])
      when is_binary(server_node_name) and is_binary(client_node_name) and is_list(opts) do
    Rclex.ParameterClient.start(server_node_name, client_node_name, opts)
  end

  @doc """
  Stop the parameter client on `client_node_name` for the given
  `server_node_name`. Same options as `start_parameter_client/3`.
  """
  @doc section: :parameter_client
  @spec stop_parameter_client(
          server_node_name :: String.t(),
          client_node_name :: String.t(),
          opts :: [namespace: String.t(), server_namespace: String.t()]
        ) :: :ok
  def stop_parameter_client(server_node_name, client_node_name, opts \\ [])
      when is_binary(server_node_name) and is_binary(client_node_name) and is_list(opts) do
    Rclex.ParameterClient.stop(server_node_name, client_node_name, opts)
  end

  @doc """
  Returns whether the remote parameter services are currently available.
  Returns `{:error, :not_found}` if the parameter client has not been started.
  """
  @doc section: :parameter_client
  @spec parameter_service_available?(
          server_node_name :: String.t(),
          client_node_name :: String.t(),
          opts :: [namespace: String.t(), server_namespace: String.t()]
        ) :: boolean() | {:error, :not_found}
  def parameter_service_available?(server_node_name, client_node_name, opts \\ [])
      when is_binary(server_node_name) and is_binary(client_node_name) and is_list(opts) do
    Rclex.ParameterClient.service_available?(server_node_name, client_node_name, opts)
  end

  @doc """
  Get the values of `parameter_names` from the remote `server_node_name`.

  Returns `{:ok, [{name, value}, ...]}` on success, where each `value` is the
  Elixir-side decoded parameter value (or `nil` if not set).

  ### opts

  - #{@namespace_doc}
  - `:server_namespace` (default `"/"`)
  - `:timeout` (seconds, float; default `nil` for infinite)
  """
  @doc section: :parameter_client
  @spec get_remote_parameters(
          server_node_name :: String.t(),
          parameter_names :: [String.t()],
          client_node_name :: String.t(),
          opts :: keyword()
        ) :: {:ok, [{String.t(), term()}]} | {:error, term()}
  def get_remote_parameters(server_node_name, parameter_names, client_node_name, opts \\ [])
      when is_binary(server_node_name) and is_list(parameter_names) and
             is_binary(client_node_name) and is_list(opts) do
    Rclex.ParameterClient.get_parameters(
      server_node_name,
      parameter_names,
      client_node_name,
      opts
    )
  end

  @doc """
  Get the parameter types of `parameter_names` on the remote node.

  Returns `{:ok, types_binary}` on success, with one byte per requested name
  matching the ROS 2 `ParameterType` constants.
  """
  @doc section: :parameter_client
  @spec get_remote_parameter_types(
          server_node_name :: String.t(),
          parameter_names :: [String.t()],
          client_node_name :: String.t(),
          opts :: keyword()
        ) :: {:ok, binary()} | {:error, term()}
  def get_remote_parameter_types(server_node_name, parameter_names, client_node_name, opts \\ [])
      when is_binary(server_node_name) and is_list(parameter_names) and
             is_binary(client_node_name) and is_list(opts) do
    Rclex.ParameterClient.get_parameter_types(
      server_node_name,
      parameter_names,
      client_node_name,
      opts
    )
  end

  @doc """
  Describe `parameter_names` on the remote node. If `parameter_names` is
  empty, all parameters are described.
  """
  @doc section: :parameter_client
  @spec describe_remote_parameters(
          server_node_name :: String.t(),
          parameter_names :: [String.t()],
          client_node_name :: String.t(),
          opts :: keyword()
        ) :: {:ok, [struct()]} | {:error, term()}
  def describe_remote_parameters(server_node_name, parameter_names, client_node_name, opts \\ [])
      when is_binary(server_node_name) and is_list(parameter_names) and
             is_binary(client_node_name) and is_list(opts) do
    Rclex.ParameterClient.describe_parameters(
      server_node_name,
      parameter_names,
      client_node_name,
      opts
    )
  end

  @doc """
  List parameters on the remote node.

  ### opts

  - `:prefixes` — list of prefixes to filter by, default `[]`
  - `:depth` — recursion depth, default `0` (unlimited)
  - #{@namespace_doc}
  - `:server_namespace`, `:timeout`
  """
  @doc section: :parameter_client
  @spec list_remote_parameters(
          server_node_name :: String.t(),
          client_node_name :: String.t(),
          opts :: keyword()
        ) :: {:ok, %{names: [String.t()], prefixes: [String.t()]}} | {:error, term()}
  def list_remote_parameters(server_node_name, client_node_name, opts \\ [])
      when is_binary(server_node_name) and is_binary(client_node_name) and is_list(opts) do
    Rclex.ParameterClient.list_parameters(server_node_name, client_node_name, opts)
  end

  @doc """
  Set parameters on the remote node, one by one.

  `parameters` is a list of `{name, value}` tuples, `{name, value, type}`
  tuples (with explicit type, see `Rclex.ParameterHelpers.gen_parameter_value_struct/2`),
  or pre-built `%Rclex.Pkgs.RclInterfaces.Msg.Parameter{}` structs.

  Returns `{:ok, [%SetParametersResult{}]}` on success.
  """
  @doc section: :parameter_client
  @spec set_remote_parameters(
          server_node_name :: String.t(),
          parameters :: [{String.t(), term()} | {String.t(), term(), atom()} | struct()],
          client_node_name :: String.t(),
          opts :: keyword()
        ) :: {:ok, [struct()]} | {:error, term()}
  def set_remote_parameters(server_node_name, parameters, client_node_name, opts \\ [])
      when is_binary(server_node_name) and is_list(parameters) and
             is_binary(client_node_name) and is_list(opts) do
    Rclex.ParameterClient.set_parameters(server_node_name, parameters, client_node_name, opts)
  end

  @doc """
  Set parameters on the remote node atomically. Either all parameters are
  applied or none.
  """
  @doc section: :parameter_client
  @spec set_remote_parameters_atomically(
          server_node_name :: String.t(),
          parameters :: [{String.t(), term()} | {String.t(), term(), atom()} | struct()],
          client_node_name :: String.t(),
          opts :: keyword()
        ) :: {:ok, struct()} | {:error, term()}
  def set_remote_parameters_atomically(server_node_name, parameters, client_node_name, opts \\ [])
      when is_binary(server_node_name) and is_list(parameters) and
             is_binary(client_node_name) and is_list(opts) do
    Rclex.ParameterClient.set_parameters_atomically(
      server_node_name,
      parameters,
      client_node_name,
      opts
    )
  end

  @doc """
  Start a subscription that forwards ROS 2 parameter events to `callback`.

  ### opts

  - #{@namespace_doc}
  - `:node_filter` — fully qualified node name to filter by (default: no filter)
  - `:parameter_filter` — list of parameter names to filter by (default: no filter)
  - `:qos` — defaults to `Rclex.QoS.profile_parameter_events/0`
  """
  @doc section: :parameter_client
  @spec start_parameter_event_handler(
          callback :: (parameter_event() -> any()),
          client_node_name :: String.t(),
          opts :: keyword()
        ) :: :ok | {:error, term()}
  def start_parameter_event_handler(callback, client_node_name, opts \\ [])
      when is_function(callback, 1) and is_binary(client_node_name) and is_list(opts) do
    Rclex.ParameterEventHandler.start(callback, client_node_name, opts)
  end

  @doc """
  Stop the parameter event handler on `client_node_name`.
  """
  @doc section: :parameter_client
  @spec stop_parameter_event_handler(client_node_name :: String.t(), opts :: keyword()) ::
          :ok | {:error, :not_found}
  def stop_parameter_event_handler(client_node_name, opts \\ [])
      when is_binary(client_node_name) and is_list(opts) do
    Rclex.ParameterEventHandler.stop(client_node_name, opts)
  end

  @doc """
  Return the number of publishers on a given topic.

  - #{@topic_name_doc}

  ### opts

  - #{@namespace_doc}

  ### Examples

      iex> alias Rclex.Pkgs.StdMsgs
      iex> Rclex.start_publisher(StdMsgs.Msg.String, "/chatter", "node", namespace: "/example")
      :ok
      iex> Rclex.count_publishers("node", "/chatter", namespace: "/example")
      1
  """
  @doc section: :graph
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

  ### Examples

      iex> alias Rclex.Pkgs.StdMsgs
      iex> Rclex.start_subscription(&IO.inspect/1, StdMsgs.Msg.String, "/chatter", "node", namespace: "/example")
      :ok
      iex> Rclex.count_subscribers("node", "/chatter", namespace: "/example")
      1
  """
  @doc section: :graph
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

  ### Examples

      iex> Rclex.get_client_names_and_types_by_node("node", "example_node", namespace: "/example")
      [{"node","/example"}]
  """
  @doc section: :graph
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

  ### Examples

      iex> Rclex.get_node_names("node", namespace: "/example")
      [{"node","/example"}]
  """
  @doc section: :graph
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

  ### Examples

      iex> Rclex.get_node_names_with_enclaves("node", namespace: "/example")
      [{"node", "/example", "/"}]
  """
  @doc section: :graph
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

  ### Examples

      iex> Rclex.get_publisher_names_and_types_by_node("node", "node", "/example", namespace: "/example")
      [{"/chatter", ["std_msgs/msg/String"]}]
  """
  @doc section: :graph
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

  ### Examples

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
  @doc section: :graph
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

  ### Examples

      iex> Rclex.get_service_names_and_types("node", namespace: "/example")
      [{"/set_test_bool", ["std_srvs/srv/SetBool"]}]
  """
  @doc section: :graph
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

  ### Examples

      iex> Rclex.get_service_names_and_types_by_node("node", "example_node", "/example", namespace: "/example")
      [{"/set_test_bool", ["std_srvs/srv/SetBool"]}]
  """
  @doc section: :graph
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

  ### Examples

      iex> Rclex.get_subscriber_names_and_types_by_node("node", "node", "/example", namespace: "/example")
      [{"/chatter", ["std_msgs/msg/String"]}]
  """
  @doc section: :graph
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

  ### Examples

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
  @doc section: :graph
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

  ### Examples

      iex> Rclex.get_topic_names_and_types("node", namespace: "/example")
      [{"/chatter", ["std_msgs/msg/String"]}]
  """
  @doc section: :graph
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
  Return a list of action server names and their types for a node.

  ### opts

  - #{@namespace_doc}

  ### Examples

      iex> Rclex.action_get_server_names_and_types_by_node("node", "/chatter", "/example")
      [{"/lookup_transform", ["tf2_msgs/action/LookupTransform"]}]
  """
  @doc section: :graph
  @spec action_get_server_names_and_types_by_node(
          name :: String.t(),
          node_name :: String.t(),
          node_namespace :: String.t(),
          opts :: [namespace: String.t()]
        ) :: [{String.t(), [String.t()]}]
  def action_get_server_names_and_types_by_node(name, node_name, node_namespace, opts \\ []) do
    namespace = Keyword.get(opts, :namespace, "/")

    Rclex.Node.action_get_server_names_and_types_by_node(
      name,
      namespace,
      node_name,
      node_namespace
    )
  end

  @doc """
  Return a list of action client names and their types for a node.

  ### opts

  - #{@namespace_doc}

  ### Examples

      iex> Rclex.action_get_client_names_and_types_by_node("node", "/chatter", "/example")
      [{"/lookup_transform", ["tf2_msgs/action/LookupTransform"]}]
  """
  @doc section: :graph
  @spec action_get_client_names_and_types_by_node(
          name :: String.t(),
          node_name :: String.t(),
          node_namespace :: String.t(),
          opts :: [namespace: String.t()]
        ) :: [{String.t(), [String.t()]}]
  def action_get_client_names_and_types_by_node(name, node_name, node_namespace, opts \\ []) do
    namespace = Keyword.get(opts, :namespace, "/")

    Rclex.Node.action_get_client_names_and_types_by_node(
      name,
      namespace,
      node_name,
      node_namespace
    )
  end

  @doc """
  Return a list of action names and their types.

  ### opts

  - #{@namespace_doc}

  ### Examples

      iex> Rclex.action_get_names_and_types("node", namespace: "/example")
      [{"/lookup_transform", ["tf2_msgs/action/LookupTransform"]}]
  """
  @doc section: :graph
  @spec action_get_names_and_types(
          name :: String.t(),
          opts :: [namespace: String.t()]
        ) :: [{String.t(), [String.t()]}]
  def action_get_names_and_types(name, opts \\ []) do
    namespace = Keyword.get(opts, :namespace, "/")
    Rclex.Node.action_get_names_and_types(name, namespace)
  end

  @doc """
  Check if a service server is available for the given service client.
  This function will return true, if there is a service server available for the given client.

  - #{@service_name_doc}

  ### opts

  - #{@namespace_doc}

  ### Examples

      iex> Rclex.service_server_available?("node", "/set_bool", namespace: "/example")
      :false
  """
  @doc section: :client
  @spec service_server_available?(
          name :: String.t(),
          service_type :: module(),
          service_name :: service_name(),
          opts :: [namespace: String.t()]
        ) :: boolean
  def service_server_available?(service_type, service_name, name, opts \\ []) do
    namespace = Keyword.get(opts, :namespace, "/")
    Rclex.Client.service_server_available?(service_type, service_name, name, namespace)
  end

  @doc """
  Create a TF2 buffer identified by `buffer_name` for a node.

  This buffer stores dynamic and static transforms and is queried by frame names.

  ### Parameters

  - `buffer_name` - Public identifier for the TF buffer (for example `"main"`).
  - `name` - Node name used to scope the buffer owner.

  ### opts

  - #{@namespace_doc}
  - `:cache_time_sec` cache duration for dynamic transforms in seconds (`float`), default `10.0`.

  ### Examples

      iex> Rclex.tf2_buffer_new("main", "node", namespace: "/robot")
      :ok
  """
  @doc section: :tf2
  @spec tf2_buffer_new(
          buffer_name :: String.t() | atom(),
          name :: String.t(),
          opts :: [namespace: String.t(), cache_time_sec: float()]
        ) :: :ok | {:error, term()}
  def tf2_buffer_new(buffer_name, name, opts \\ [])
      when (is_binary(buffer_name) or is_atom(buffer_name)) and is_binary(name) and is_list(opts) do
    Rclex.Tf2.buffer_new(buffer_name, name, opts)
  end

  @doc """
  Destroy a TF2 buffer identified by `buffer_name` for a node.

  ### Parameters

  - `buffer_name` - Buffer identifier passed to `tf2_buffer_new/3`.
  - `name` - Node name used when creating the buffer.

  ### opts

  - #{@namespace_doc}

  ### Examples

      iex> Rclex.tf2_buffer_destroy("main", "node", namespace: "/robot")
      :ok
  """
  @doc section: :tf2
  @spec tf2_buffer_destroy(
          buffer_name :: String.t() | atom(),
          name :: String.t(),
          opts :: [namespace: String.t()]
        ) :: :ok | {:error, term()}
  def tf2_buffer_destroy(buffer_name, name, opts \\ [])
      when (is_binary(buffer_name) or is_atom(buffer_name)) and is_binary(name) and is_list(opts) do
    Rclex.Tf2.buffer_destroy(buffer_name, name, opts)
  end

  @doc """
  Insert or update a TF2 transform in the buffer.

  Dynamic transforms are time-aware and can be interpolated for lookup queries.

  ### Parameters

  - `buffer_name` - Buffer identifier.
  - `transform_stamped` - Map/struct compatible with `geometry_msgs/TransformStamped` shape.
  - `authority` - Optional broadcaster identifier for diagnostics.
  - `name` - Node name used to resolve the buffer.

  ### opts

  - #{@namespace_doc}

  ### Examples

      iex> ts = %{
      ...>   header: %{frame_id: "map", stamp: %{sec: 10, nanosec: 0}},
      ...>   child_frame_id: "base_link",
      ...>   transform: %{
      ...>     translation: %{x: 1.0, y: 0.0, z: 0.0},
      ...>     rotation: %{w: 1.0, x: 0.0, y: 0.0, z: 0.0}
      ...>   }
      ...> }
      iex> Rclex.tf2_set_transform("main", ts, "odometry", "node", namespace: "/robot")
      :ok
  """
  @doc section: :tf2
  @spec tf2_set_transform(
          buffer_name :: String.t() | atom(),
          transform_stamped :: map() | struct(),
          authority :: String.t(),
          name :: String.t(),
          opts :: [namespace: String.t()]
        ) :: :ok | {:error, term()}
  def tf2_set_transform(buffer_name, transform_stamped, authority \\ "", name, opts \\ [])
      when (is_binary(buffer_name) or is_atom(buffer_name)) and
             (is_map(transform_stamped) or is_struct(transform_stamped)) and is_binary(authority) and
             is_binary(name) and is_list(opts) do
    Rclex.Tf2.set_transform(buffer_name, transform_stamped, authority, name, opts)
  end

  @doc """
  Insert or update a static TF2 transform in the buffer.

  Static transforms are treated as valid across time and are not subject to
  dynamic cache extrapolation behavior.

  ### Parameters

  - `buffer_name` - Buffer identifier.
  - `transform_stamped` - Map/struct compatible with `geometry_msgs/TransformStamped` shape.
  - `authority` - Optional broadcaster identifier for diagnostics.
  - `name` - Node name used to resolve the buffer.

  ### opts

  - #{@namespace_doc}

  ### Examples

      iex> ts = %{
      ...>   header: %{frame_id: "base_link", stamp: %{sec: 0, nanosec: 0}},
      ...>   child_frame_id: "camera_link",
      ...>   transform: %{
      ...>     translation: %{x: 0.2, y: 0.0, z: 0.1},
      ...>     rotation: %{w: 1.0, x: 0.0, y: 0.0, z: 0.0}
      ...>   }
      ...> }
      iex> Rclex.tf2_set_transform_static("main", ts, "urdf", "node")
      :ok
  """
  @doc section: :tf2
  @spec tf2_set_transform_static(
          buffer_name :: String.t() | atom(),
          transform_stamped :: map() | struct(),
          authority :: String.t(),
          name :: String.t(),
          opts :: [namespace: String.t()]
        ) :: :ok | {:error, term()}
  def tf2_set_transform_static(buffer_name, transform_stamped, authority \\ "", name, opts \\ [])
      when (is_binary(buffer_name) or is_atom(buffer_name)) and
             (is_map(transform_stamped) or is_struct(transform_stamped)) and is_binary(authority) and
             is_binary(name) and is_list(opts) do
    Rclex.Tf2.set_transform_static(buffer_name, transform_stamped, authority, name, opts)
  end

  @doc """
  Clear all TF2 data (dynamic and static) from a buffer.

  ### Parameters

  - `buffer_name` - Buffer identifier.
  - `name` - Node name used to resolve the buffer.

  ### opts

  - #{@namespace_doc}

  ### Examples

      iex> Rclex.tf2_clear("main", "node", namespace: "/robot")
      :ok
  """
  @doc section: :tf2
  @spec tf2_clear(
          buffer_name :: String.t() | atom(),
          name :: String.t(),
          opts :: [namespace: String.t()]
        ) ::
          :ok | {:error, term()}
  def tf2_clear(buffer_name, name, opts \\ [])
      when (is_binary(buffer_name) or is_atom(buffer_name)) and is_binary(name) and is_list(opts) do
    Rclex.Tf2.clear(buffer_name, name, opts)
  end

  @doc """
  Return known TF2 frames as YAML.

  The output is intended for diagnostics and mirrors the common TF2 frame-graph
  style: entries include parent frame, broadcaster, rate, latest/oldest
  transform time, and buffer length.

  ### Parameters

  - `buffer_name` - Buffer identifier.
  - `name` - Node name used to resolve the buffer.

  ### opts

  - #{@namespace_doc}

  ### Examples

      iex> {:ok, yaml} = Rclex.tf2_all_frames_as_yaml("main", "node")
      iex> is_binary(yaml)
      true
  """
  @doc section: :tf2
  @spec tf2_all_frames_as_yaml(
          buffer_name :: String.t() | atom(),
          name :: String.t(),
          opts :: [namespace: String.t()]
        ) :: {:ok, String.t()} | {:error, term()}
  def tf2_all_frames_as_yaml(buffer_name, name, opts \\ [])
      when (is_binary(buffer_name) or is_atom(buffer_name)) and is_binary(name) and is_list(opts) do
    Rclex.Tf2.all_frames_as_yaml(buffer_name, name, opts)
  end

  @doc """
  Return latest common timestamp (ns) between two frames.

  This follows the TF2 "latest common time" concept and is useful when
  performing `time_ns = 0` (latest) lookups.

  ### Parameters

  - `buffer_name` - Buffer identifier.
  - `target_frame` - Destination frame.
  - `source_frame` - Source frame.
  - `name` - Node name used to resolve the buffer.

  ### opts

  - #{@namespace_doc}

  ### Examples

      iex> {:ok, ns} = Rclex.tf2_get_latest_common_time("main", "map", "base_link", "node")
      iex> is_integer(ns)
      true
  """
  @doc section: :tf2
  @spec tf2_get_latest_common_time(
          buffer_name :: String.t() | atom(),
          target_frame :: String.t(),
          source_frame :: String.t(),
          name :: String.t(),
          opts :: [namespace: String.t()]
        ) :: {:ok, integer()} | {:error, term()}
  def tf2_get_latest_common_time(buffer_name, target_frame, source_frame, name, opts \\ [])
      when (is_binary(buffer_name) or is_atom(buffer_name)) and is_binary(target_frame) and
             is_binary(source_frame) and is_binary(name) and is_list(opts) do
    Rclex.Tf2.get_latest_common_time(buffer_name, target_frame, source_frame, name, opts)
  end

  @doc """
  Start TF topic listeners for `/tf` and `/tf_static` and feed incoming transforms
  into the specified TF2 buffer.

  This is the ROS transport counterpart to `tf2_set_transform/5` and
  `tf2_set_transform_static/5`.

  ### Parameters

  - `buffer_name` - TF2 buffer identifier.
  - `name` - Node name that owns the subscriptions.

  ### opts

  - #{@namespace_doc}
  - `:authority` authority string attached to ingested transforms (default `"tf_listener"`).
  - `:tf_message_type_module` override TF message module (default `Rclex.Pkgs.Tf2Msgs.Msg.TFMessage`).

  ### Notes

  Requires generated message type `tf2_msgs/msg/TFMessage`.
  """
  @doc section: :tf2
  @spec tf2_start_listener(
          buffer_name :: String.t() | atom(),
          name :: String.t(),
          opts :: [namespace: String.t(), authority: String.t(), tf_message_type_module: module()]
        ) :: :ok | {:error, term()}
  def tf2_start_listener(buffer_name, name, opts \\ [])
      when (is_binary(buffer_name) or is_atom(buffer_name)) and is_binary(name) and is_list(opts) do
    Rclex.Tf2.start_listener(buffer_name, name, opts)
  end

  @doc """
  Stop TF topic listeners (`/tf`, `/tf_static`) for the given buffer and node.

  ### opts

  - #{@namespace_doc}
  - `:tf_message_type_module` override TF message module (default `Rclex.Pkgs.Tf2Msgs.Msg.TFMessage`).
  """
  @doc section: :tf2
  @spec tf2_stop_listener(
          buffer_name :: String.t() | atom(),
          name :: String.t(),
          opts :: [namespace: String.t(), tf_message_type_module: module()]
        ) :: :ok | {:error, term()}
  def tf2_stop_listener(buffer_name, name, opts \\ [])
      when (is_binary(buffer_name) or is_atom(buffer_name)) and is_binary(name) and is_list(opts) do
    Rclex.Tf2.stop_listener(buffer_name, name, opts)
  end

  @doc """
  Start TF topic publishers for `/tf` and `/tf_static`.

  ### Parameters

  - `name` - Node name that owns the publishers.

  ### opts

  - #{@namespace_doc}
  - `:tf_message_type_module` override TF message module (default `Rclex.Pkgs.Tf2Msgs.Msg.TFMessage`).
  """
  @doc section: :tf2
  @spec tf2_start_broadcaster(
          name :: String.t(),
          opts :: [namespace: String.t(), tf_message_type_module: module()]
        ) :: :ok | {:error, term()}
  def tf2_start_broadcaster(name, opts \\ []) when is_binary(name) and is_list(opts) do
    Rclex.Tf2.start_broadcaster(name, opts)
  end

  @doc """
  Stop TF topic publishers for `/tf` and `/tf_static`.

  ### opts

  - #{@namespace_doc}
  - `:tf_message_type_module` override TF message module (default `Rclex.Pkgs.Tf2Msgs.Msg.TFMessage`).
  """
  @doc section: :tf2
  @spec tf2_stop_broadcaster(
          name :: String.t(),
          opts :: [namespace: String.t(), tf_message_type_module: module()]
        ) :: :ok | {:error, term()}
  def tf2_stop_broadcaster(name, opts \\ []) when is_binary(name) and is_list(opts) do
    Rclex.Tf2.stop_broadcaster(name, opts)
  end

  @doc """
  Publish one or more dynamic transforms to `/tf`.

  ### Parameters

  - `transform_stamped_or_list` - A `TransformStamped`-compatible map/struct or a list of them.
  - `name` - Node name that owns the publisher.

  ### opts

  - #{@namespace_doc}
  - `:tf_message_type_module` override TF message module (default `Rclex.Pkgs.Tf2Msgs.Msg.TFMessage`).
  """
  @doc section: :tf2
  @spec tf2_broadcast_dynamic(
          transform_stamped_or_list :: map() | struct() | [map() | struct()],
          name :: String.t(),
          opts :: [namespace: String.t(), tf_message_type_module: module()]
        ) :: :ok | {:error, term()}
  def tf2_broadcast_dynamic(transform_stamped_or_list, name, opts \\ [])
      when (is_map(transform_stamped_or_list) or is_struct(transform_stamped_or_list) or
              is_list(transform_stamped_or_list)) and is_binary(name) and is_list(opts) do
    Rclex.Tf2.broadcast_dynamic(transform_stamped_or_list, name, opts)
  end

  @doc """
  Publish one or more static transforms to `/tf_static`.

  ### Parameters

  - `transform_stamped_or_list` - A `TransformStamped`-compatible map/struct or a list of them.
  - `name` - Node name that owns the publisher.

  ### opts

  - #{@namespace_doc}
  - `:tf_message_type_module` override TF message module (default `Rclex.Pkgs.Tf2Msgs.Msg.TFMessage`).
  """
  @doc section: :tf2
  @spec tf2_broadcast_static(
          transform_stamped_or_list :: map() | struct() | [map() | struct()],
          name :: String.t(),
          opts :: [namespace: String.t(), tf_message_type_module: module()]
        ) :: :ok | {:error, term()}
  def tf2_broadcast_static(transform_stamped_or_list, name, opts \\ [])
      when (is_map(transform_stamped_or_list) or is_struct(transform_stamped_or_list) or
              is_list(transform_stamped_or_list)) and is_binary(name) and is_list(opts) do
    Rclex.Tf2.broadcast_static(transform_stamped_or_list, name, opts)
  end

  @doc """
  Check whether a TF2 transform is available within timeout.

  `timeout_sec` is in seconds (`float`).

  `time_ns` semantics:

  - `0` => latest common time lookup
  - `> 0` => lookup at specific timestamp (ns)

  ### Parameters

  - `buffer_name` - Buffer identifier.
  - `target_frame` - Destination frame.
  - `source_frame` - Source frame.
  - `time_ns` - Query timestamp in nanoseconds (`0` means latest).
  - `timeout_sec` - Maximum wait duration in seconds.
  - `name` - Node name used to resolve the buffer.

  ### opts

  - #{@namespace_doc}
  - `:return_debug_tuple` when `true`, returns `{boolean, reason}`.

  ### Examples

      iex> Rclex.tf2_can_transform?("main", "map", "base_link", 0, 0.1, "node")
      true

      iex> Rclex.tf2_can_transform?("main", "map", "unknown", 0, 0.0, "node", return_debug_tuple: true)
      {false, "frame connectivity failed"}
  """
  @doc section: :tf2
  @spec tf2_can_transform?(
          buffer_name :: String.t() | atom(),
          target_frame :: String.t(),
          source_frame :: String.t(),
          time_ns :: integer(),
          timeout_sec :: float(),
          name :: String.t(),
          opts :: [namespace: String.t(), return_debug_tuple: boolean()]
        ) :: boolean() | {boolean(), String.t()} | {:error, term()}
  def tf2_can_transform?(
        buffer_name,
        target_frame,
        source_frame,
        time_ns,
        timeout_sec \\ 0.0,
        name,
        opts \\ []
      )
      when (is_binary(buffer_name) or is_atom(buffer_name)) and is_binary(target_frame) and
             is_binary(source_frame) and is_integer(time_ns) and is_number(timeout_sec) and
             is_binary(name) and is_list(opts) do
    Rclex.Tf2.can_transform?(
      buffer_name,
      target_frame,
      source_frame,
      time_ns,
      timeout_sec,
      name,
      opts
    )
  end

  @doc """
  Lookup a TF2 transform within timeout.

  `timeout_sec` is in seconds (`float`).

  `time_ns` semantics:

  - `0` => latest common time lookup
  - `> 0` => lookup at specific timestamp (ns)

  Possible errors include connectivity and extrapolation (`:extrapolation_past`
  or `:extrapolation_future`) depending on the query time and cached data.

  ### Parameters

  - `buffer_name` - Buffer identifier.
  - `target_frame` - Destination frame.
  - `source_frame` - Source frame.
  - `time_ns` - Query timestamp in nanoseconds (`0` means latest).
  - `timeout_sec` - Maximum wait duration in seconds.
  - `name` - Node name used to resolve the buffer.

  ### opts

  - #{@namespace_doc}

  ### Examples

      iex> {:ok, tf} =
      ...>   Rclex.tf2_lookup_transform(
      ...>     "main",
      ...>     "map",
      ...>     "base_link",
      ...>     0,
      ...>     0.1,
      ...>     "node",
      ...>     namespace: "/robot"
      ...>   )
      iex> tf.header.frame_id
      "map"
  """
  @doc section: :tf2
  @spec tf2_lookup_transform(
          buffer_name :: String.t() | atom(),
          target_frame :: String.t(),
          source_frame :: String.t(),
          time_ns :: integer(),
          timeout_sec :: float(),
          name :: String.t(),
          opts :: [namespace: String.t()]
        ) :: {:ok, map()} | {:error, term()}
  def tf2_lookup_transform(
        buffer_name,
        target_frame,
        source_frame,
        time_ns,
        timeout_sec \\ 0.0,
        name,
        opts \\ []
      )
      when (is_binary(buffer_name) or is_atom(buffer_name)) and is_binary(target_frame) and
             is_binary(source_frame) and is_integer(time_ns) and is_number(timeout_sec) and
             is_binary(name) and is_list(opts) do
    Rclex.Tf2.lookup_transform(
      buffer_name,
      target_frame,
      source_frame,
      time_ns,
      timeout_sec,
      name,
      opts
    )
  end
end
