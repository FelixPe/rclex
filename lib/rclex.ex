defmodule Rclex do
  @moduledoc """
  User API for `#{__MODULE__}`.
  """

  @namespace_doc "`:namespace` must lead with \"/\". if not specified, the default is \"/\""
  @qos_doc "`:qos` if not specified, applied the default which equals return of `Rclex.QoS.profile_default/0`"
  @topic_name_doc "`topic_name` must lead with \"/\". See all [constraints](https://design.ros2.org/articles/topic_and_service_names.html#ros-2-topic-and-service-name-constraints)"
  @service_name_doc "`service_name` must lead with \"/\". See all [constraints](https://design.ros2.org/articles/topic_and_service_names.html#ros-2-topic-and-service-name-constraints)"

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
end
