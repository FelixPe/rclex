defmodule Rclex.LifecycleNode do
  @moduledoc """
  A managed (lifecycle) node implementing the ROS 2 [Managed Node design](https://design.ros.org/articles/node_lifecycle.html).

  A `Rclex.LifecycleNode` wraps a regular Rclex node and adds the four
  primary states (`:unconfigured`, `:inactive`, `:active`, `:finalized`)
  with the corresponding transitions. The five standard lifecycle services
  are exposed under the node's namespace:

    * `~/change_state`               (`lifecycle_msgs/srv/ChangeState`)
    * `~/get_state`                  (`lifecycle_msgs/srv/GetState`)
    * `~/get_available_states`       (`lifecycle_msgs/srv/GetAvailableStates`)
    * `~/get_available_transitions`  (`lifecycle_msgs/srv/GetAvailableTransitions`)
    * `~/get_transition_graph`       (`lifecycle_msgs/srv/GetAvailableTransitions`)

  ## Usage

      defmodule MyNode do
        use Rclex.LifecycleNode

        @impl true
        def on_configure(_state) do
          # acquire resources...
          {:ok, %{}}
        end

        @impl true
        def on_activate(_state) do
          # start publishing, etc.
          {:ok, %{}}
        end
      end

      Rclex.start_lifecycle_node(MyNode, "managed_node", namespace: "/example")
      Rclex.lifecycle_change_state("managed_node", :configure, namespace: "/example")
      Rclex.lifecycle_change_state("managed_node", :activate, namespace: "/example")

  ## Callbacks

  All callbacks are optional and default to `{:ok, user_state}`. Each
  receives the current `t:user_state/0` and may return:

    * `{:ok, new_user_state}`     — transition succeeds
    * `{:error, new_user_state}`  — transition fails (rolls back to the
      previous primary state)
    * `{:fatal, new_user_state}`  — transition errors; goes to `:finalized`

  Available callbacks:

    * `on_configure/1`
    * `on_cleanup/1`
    * `on_activate/1`
    * `on_deactivate/1`
    * `on_shutdown/1`
    * `on_error/1`
  """

  use GenServer, restart: :transient

  # NOTE: The `Rclex.Pkgs.LifecycleMsgs.*` modules are generated at build time
  # by `mix rclex.gen` (auto-injected via `msg_types_for_lifecycle/0`). To
  # avoid creating a hard compile-time dependency on those generated modules
  # we never `alias` them and only refer to them via fully-qualified names
  # inside function bodies (constructed with `struct/2` or via module
  # attributes / `apply/3`), matching the pattern used in
  # `Rclex.ActionServer`.

  @msg_state Module.concat([Rclex, Pkgs, LifecycleMsgs, Msg, State])
  @msg_transition Module.concat([Rclex, Pkgs, LifecycleMsgs, Msg, Transition])
  @msg_transition_event Module.concat([Rclex, Pkgs, LifecycleMsgs, Msg, TransitionEvent])
  @msg_transition_description Module.concat([
                                Rclex,
                                Pkgs,
                                LifecycleMsgs,
                                Msg,
                                TransitionDescription
                              ])
  @srv_change_state Module.concat([Rclex, Pkgs, LifecycleMsgs, Srv, ChangeState])
  @srv_get_state Module.concat([Rclex, Pkgs, LifecycleMsgs, Srv, GetState])
  @srv_get_available_states Module.concat([Rclex, Pkgs, LifecycleMsgs, Srv, GetAvailableStates])
  @srv_get_available_transitions Module.concat([
                                   Rclex,
                                   Pkgs,
                                   LifecycleMsgs,
                                   Srv,
                                   GetAvailableTransitions
                                 ])

  @type user_state :: any()
  @type primary_state :: :unconfigured | :inactive | :active | :finalized
  @type transition ::
          :configure | :cleanup | :activate | :deactivate | :shutdown
  @type callback_result ::
          {:ok, user_state()} | {:error, user_state()} | {:fatal, user_state()}

  ## ---------- behaviour ----------

  @callback on_configure(user_state()) :: callback_result()
  @callback on_cleanup(user_state()) :: callback_result()
  @callback on_activate(user_state()) :: callback_result()
  @callback on_deactivate(user_state()) :: callback_result()
  @callback on_shutdown(user_state()) :: callback_result()
  @callback on_error(user_state()) :: callback_result()

  @optional_callbacks on_configure: 1,
                      on_cleanup: 1,
                      on_activate: 1,
                      on_deactivate: 1,
                      on_shutdown: 1,
                      on_error: 1

  defmacro __using__(_opts) do
    quote do
      @behaviour Rclex.LifecycleNode

      def on_configure(state), do: {:ok, state}
      def on_cleanup(state), do: {:ok, state}
      def on_activate(state), do: {:ok, state}
      def on_deactivate(state), do: {:ok, state}
      def on_shutdown(state), do: {:ok, state}
      def on_error(state), do: {:ok, state}

      defoverridable on_configure: 1,
                     on_cleanup: 1,
                     on_activate: 1,
                     on_deactivate: 1,
                     on_shutdown: 1,
                     on_error: 1
    end
  end

  ## ---------- registry helpers ----------

  @doc false
  def name(node_name, namespace \\ "/") do
    {:global, {:lifecycle_node, node_name, namespace}}
  end

  ## ---------- public API ----------

  @doc false
  def start_link(args) do
    node_name = Keyword.fetch!(args, :node_name)
    namespace = Keyword.get(args, :namespace, "/")
    GenServer.start_link(__MODULE__, args, name: name(node_name, namespace))
  end

  @doc "Return the current primary state."
  @spec get_state(String.t(), keyword()) :: primary_state()
  def get_state(node_name, opts \\ []) do
    namespace = Keyword.get(opts, :namespace, "/")
    GenServer.call(name(node_name, namespace), :get_state)
  end

  @doc "Return the current user state (whatever the user callbacks return)."
  @spec get_user_state(String.t(), keyword()) :: user_state()
  def get_user_state(node_name, opts \\ []) do
    namespace = Keyword.get(opts, :namespace, "/")
    GenServer.call(name(node_name, namespace), :get_user_state)
  end

  @doc """
  Trigger a transition. Returns `:ok` if the transition succeeded,
  `{:error, reason}` otherwise.
  """
  @spec change_state(String.t(), transition(), keyword()) ::
          :ok | {:error, :invalid_transition | :callback_failed | :callback_errored}
  def change_state(node_name, transition, opts \\ []) when is_atom(transition) do
    namespace = Keyword.get(opts, :namespace, "/")
    GenServer.call(name(node_name, namespace), {:change_state, transition})
  end

  ## ---------- callbacks ----------

  @impl true
  def init(args) do
    Process.flag(:trap_exit, true)

    node_name = Keyword.fetch!(args, :node_name)
    namespace = Keyword.get(args, :namespace, "/")
    impl_module = Keyword.fetch!(args, :impl_module)
    user_state = Keyword.get(args, :user_state, %{})

    case Rclex.start_node(node_name, namespace: namespace) do
      :ok -> :ok
      {:error, :already_started} -> :ok
      {:error, reason} -> throw({:stop, {:start_node_failed, reason}})
    end

    :ok = register_lifecycle_services(node_name, namespace)
    :ok = register_transition_publisher(node_name, namespace)

    {:ok,
     %{
       node_name: node_name,
       namespace: namespace,
       impl_module: impl_module,
       user_state: user_state,
       primary_state: :unconfigured
     }}
  catch
    {:stop, reason} -> {:stop, reason}
  end

  @impl true
  def terminate(_reason, %{node_name: node_name, namespace: namespace}) do
    # best-effort cleanup; ignore errors since some entities may already be down
    for {suffix, srv_module} <- lifecycle_services() do
      _ =
        catch_errors(fn ->
          Rclex.stop_service(srv_module, service_path(node_name, suffix), node_name,
            namespace: namespace
          )
        end)
    end

    _ =
      catch_errors(fn ->
        Rclex.stop_publisher(@msg_transition_event, transition_event_topic(node_name), node_name,
          namespace: namespace
        )
      end)

    _ = catch_errors(fn -> Rclex.stop_node(node_name, namespace: namespace) end)
    :ok
  end

  defp catch_errors(fun) do
    try do
      fun.()
    rescue
      _ -> :ok
    catch
      _, _ -> :ok
    end
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state.primary_state, state}
  end

  def handle_call(:get_user_state, _from, state) do
    {:reply, state.user_state, state}
  end

  def handle_call({:change_state, transition}, _from, state) do
    case do_transition(transition, state) do
      {:ok, new_state} -> {:reply, :ok, new_state}
      {:error, reason, new_state} -> {:reply, {:error, reason}, new_state}
    end
  end

  ## ---------- service callbacks (called from request-handling tasks) ----------

  @doc false
  def handle_change_state(%{transition: %{id: tid}}, node_name, namespace) do
    transition = transition_id_to_atom(tid)

    success? =
      if transition do
        case change_state(node_name, transition, namespace: namespace) do
          :ok -> true
          _ -> false
        end
      else
        false
      end

    struct(Module.concat(@srv_change_state, Response), %{success: success?})
  end

  @doc false
  def handle_get_state(_request, node_name, namespace) do
    primary = get_state(node_name, namespace: namespace)

    struct(Module.concat(@srv_get_state, Response), %{
      current_state: primary_state_to_msg(primary)
    })
  end

  @doc false
  def handle_get_available_states(_request, _node_name, _namespace) do
    struct(Module.concat(@srv_get_available_states, Response), %{
      available_states: all_primary_state_msgs()
    })
  end

  @doc false
  def handle_get_available_transitions(_request, node_name, namespace) do
    primary = get_state(node_name, namespace: namespace)

    descs =
      for transition <- available_transitions(primary) do
        struct(@msg_transition_description, %{
          transition: transition_atom_to_msg(transition),
          start_state: primary_state_to_msg(primary),
          goal_state: primary_state_to_msg(after_state(primary, transition))
        })
      end

    struct(Module.concat(@srv_get_available_transitions, Response), %{
      available_transitions: descs
    })
  end

  ## ---------- internal: state machine ----------

  # Allowed transitions from each primary state.
  defp available_transitions(:unconfigured), do: [:configure, :shutdown]
  defp available_transitions(:inactive), do: [:cleanup, :activate, :shutdown]
  defp available_transitions(:active), do: [:deactivate, :shutdown]
  defp available_transitions(:finalized), do: []

  defp after_state(:unconfigured, :configure), do: :inactive
  defp after_state(:unconfigured, :shutdown), do: :finalized
  defp after_state(:inactive, :cleanup), do: :unconfigured
  defp after_state(:inactive, :activate), do: :active
  defp after_state(:inactive, :shutdown), do: :finalized
  defp after_state(:active, :deactivate), do: :inactive
  defp after_state(:active, :shutdown), do: :finalized

  defp transition_to_callback(:configure), do: :on_configure
  defp transition_to_callback(:cleanup), do: :on_cleanup
  defp transition_to_callback(:activate), do: :on_activate
  defp transition_to_callback(:deactivate), do: :on_deactivate
  defp transition_to_callback(:shutdown), do: :on_shutdown

  defp do_transition(transition, %{primary_state: primary} = state) do
    if transition in available_transitions(primary) do
      callback = transition_to_callback(transition)
      target = after_state(primary, transition)

      previous = primary
      publish_transition(state, transition, previous, target)

      result =
        try do
          apply(state.impl_module, callback, [state.user_state])
        rescue
          e -> {:fatal, {:rescued, e}}
        catch
          kind, reason -> {:fatal, {kind, reason}}
        end

      case result do
        {:ok, new_user} ->
          new_state = %{state | primary_state: target, user_state: new_user}
          {:ok, new_state}

        {:error, new_user} ->
          new_state = %{state | user_state: new_user}
          {:error, :callback_failed, new_state}

        {:fatal, new_user} ->
          # invoke on_error then go to finalized regardless
          new_user2 =
            try do
              case apply(state.impl_module, :on_error, [new_user]) do
                {:ok, ns} -> ns
                {_, ns} -> ns
              end
            rescue
              _ -> new_user
            catch
              _, _ -> new_user
            end

          new_state = %{state | user_state: new_user2, primary_state: :finalized}
          {:error, :callback_errored, new_state}
      end
    else
      {:error, :invalid_transition, state}
    end
  end

  ## ---------- transition publisher ----------

  defp transition_event_topic(node_name), do: "/#{node_name}/transition_event"

  defp register_transition_publisher(node_name, namespace) do
    case Rclex.start_publisher(
           @msg_transition_event,
           transition_event_topic(node_name),
           node_name,
           namespace: namespace
         ) do
      :ok ->
        :ok

      {:error, :already_started} ->
        :ok

      {:error, reason} ->
        raise "lifecycle: failed to start transition publisher: #{inspect(reason)}"
    end
  end

  defp publish_transition(state, transition, from, to) do
    msg =
      struct(@msg_transition_event, %{
        timestamp: 0,
        transition: transition_atom_to_msg(transition),
        start_state: primary_state_to_msg(from),
        goal_state: primary_state_to_msg(to)
      })

    _ =
      Rclex.publish(msg, transition_event_topic(state.node_name), state.node_name,
        namespace: state.namespace
      )

    :ok
  end

  ## ---------- service registration ----------

  defp service_path(node_name, suffix), do: "/#{node_name}/#{suffix}"

  defp lifecycle_services() do
    [
      {"change_state", @srv_change_state},
      {"get_state", @srv_get_state},
      {"get_available_states", @srv_get_available_states},
      {"get_available_transitions", @srv_get_available_transitions},
      {"get_transition_graph", @srv_get_available_transitions}
    ]
  end

  defp register_lifecycle_services(node_name, namespace) do
    me_node_name = node_name
    me_ns = namespace

    handlers = %{
      "change_state" => fn req -> handle_change_state(req, me_node_name, me_ns) end,
      "get_state" => fn req -> handle_get_state(req, me_node_name, me_ns) end,
      "get_available_states" => fn req ->
        handle_get_available_states(req, me_node_name, me_ns)
      end,
      "get_available_transitions" => fn req ->
        handle_get_available_transitions(req, me_node_name, me_ns)
      end,
      "get_transition_graph" => fn req ->
        handle_get_available_transitions(req, me_node_name, me_ns)
      end
    }

    for {suffix, srv_module} <- lifecycle_services() do
      service_name = service_path(node_name, suffix)
      callback = Map.fetch!(handlers, suffix)

      case Rclex.start_service(callback, srv_module, service_name, node_name,
             namespace: namespace
           ) do
        :ok -> :ok
        {:error, :already_started} -> :ok
        {:error, reason} -> raise "lifecycle: failed to start #{service_name}: #{inspect(reason)}"
      end
    end

    :ok
  end

  ## ---------- conversions ----------

  defp primary_state_id(:unconfigured), do: 1
  defp primary_state_id(:inactive), do: 2
  defp primary_state_id(:active), do: 3
  defp primary_state_id(:finalized), do: 4

  defp primary_state_label(:unconfigured), do: "unconfigured"
  defp primary_state_label(:inactive), do: "inactive"
  defp primary_state_label(:active), do: "active"
  defp primary_state_label(:finalized), do: "finalized"

  @doc false
  def primary_state_to_msg(atom) when atom in [:unconfigured, :inactive, :active, :finalized] do
    struct(@msg_state, %{id: primary_state_id(atom), label: primary_state_label(atom)})
  end

  defp all_primary_state_msgs() do
    Enum.map([:unconfigured, :inactive, :active, :finalized], &primary_state_to_msg/1)
  end

  # IDs come from `lifecycle_msgs/msg/Transition` (constants).
  defp transition_id(:configure), do: 1
  defp transition_id(:cleanup), do: 2
  defp transition_id(:activate), do: 3
  defp transition_id(:deactivate), do: 4
  # Three shutdown variants exist per source state; we use the inactive one
  # as the canonical id when emitting a transition.
  defp transition_id(:shutdown), do: 6

  defp transition_atom_to_msg(atom) do
    struct(@msg_transition, %{id: transition_id(atom), label: Atom.to_string(atom)})
  end

  # Transition IDs in lifecycle_msgs:
  #   1=configure, 2=cleanup, 3=activate, 4=deactivate,
  #   5=unconfigured_shutdown, 6=inactive_shutdown, 7=active_shutdown
  defp transition_id_to_atom(1), do: :configure
  defp transition_id_to_atom(2), do: :cleanup
  defp transition_id_to_atom(3), do: :activate
  defp transition_id_to_atom(4), do: :deactivate
  defp transition_id_to_atom(id) when id in [5, 6, 7], do: :shutdown
  defp transition_id_to_atom(_), do: nil
end
