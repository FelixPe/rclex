defmodule RclexTest do
  use ExUnit.Case

  import ExUnit.CaptureLog

  alias Rclex.Pkgs.Tf2Msgs
  alias Rclex.Pkgs.StdMsgs
  alias Rclex.Pkgs.StdSrvs
  alias Rclex.Pkgs.RclInterfaces
  alias Rclex.Pkgs.Tf2Msgs.Msg.TF2Error
  alias Rclex.Pkgs.Tf2Msgs.Action
  alias Rclex.NodeSupervisor

  setup do
    :ok = Application.ensure_started(:rclex)
    on_exit(fn -> capture_log(fn -> Application.stop(:rclex) end) end)
  end

  describe "node" do
    test "start_node/1" do
      assert :ok = Rclex.start_node("name")
      assert {:error, :already_started} = Rclex.start_node("name")

      assert is_pid(GenServer.whereis(NodeSupervisor.name("name"))) == true
    end

    test "start_node/1, wrong node name" do
      assert {:error, _} = Rclex.start_node("/name")
    end

    test "stop_node/1" do
      :ok = Rclex.start_node("name")
      true = is_pid(GenServer.whereis(NodeSupervisor.name("name")))

      assert capture_log(fn -> :ok = Rclex.stop_node("name") end) =~ "Node: :shutdown"
      assert {:error, :not_found} = Rclex.stop_node("name")

      assert is_nil(GenServer.whereis(NodeSupervisor.name("name")))
    end

    test "stop_node/1, node doesn't exist" do
      assert {:error, :not_found} = Rclex.stop_node("notexists")
    end

    test "stop_node/1, confirm shutdown order" do
      :ok = Rclex.start_node("name")
      :ok = Rclex.start_publisher(StdMsgs.Msg.String, "/chatter", "name")
      :ok = Rclex.start_subscription(fn _msg -> nil end, StdMsgs.Msg.String, "/chatter", "name")
      :ok = Rclex.start_timer(1000, fn -> nil end, "timer", "name")

      logs =
        capture_log(fn -> :ok = Rclex.stop_node("name") end)
        |> String.split("\n")
        |> Enum.filter(&String.contains?(&1, ":shutdown"))

      assert Enum.count(logs) == 12
      assert List.last(logs) =~ "Node: :shutdown"
    end

    test "start_node\2, graph change events" do
      me = self()
      graph_change_callback = fn -> send(me, :graph_changed) end

      :ok = Rclex.start_node("name", namespace: "/", graph_change_callback: graph_change_callback)
      assert_receive :graph_changed
      :ok = Rclex.start_publisher(StdMsgs.Msg.String, "/chatter", "name", namespace: "/")
      assert_receive :graph_changed

      :ok =
        Rclex.start_subscription(fn _msg -> nil end, StdMsgs.Msg.String, "/chatter", "name",
          namespace: "/"
        )

      assert_receive :graph_changed
      :ok = Rclex.start_timer(1000, fn -> nil end, "timer", "name", namespace: "/")

      logs =
        capture_log(fn ->
          :ok = Rclex.stop_node("name", namespace: "/")
          assert_receive :graph_changed
          assert_receive :graph_changed
        end)
        |> String.split("\n")
        |> Enum.filter(&String.contains?(&1, ":shutdown"))

      assert Enum.count(logs) == 12
      assert List.last(logs) =~ "Node: :shutdown"
    end
  end

  describe "publisher" do
    setup do
      :ok = Rclex.start_node("name")
      on_exit(fn -> capture_log(fn -> Rclex.stop_node("name") end) end)
    end

    test "start_publisher/3" do
      assert :ok = Rclex.start_publisher(StdMsgs.Msg.String, "/chatter", "name")

      assert {:error, :already_started} =
               Rclex.start_publisher(StdMsgs.Msg.String, "/chatter", "name")
    end

    test "start_publisher/3, node doesn't exist" do
      assert {:noproc, _} =
               catch_exit(Rclex.start_publisher(StdMsgs.Msg.String, "/chatter", "notexists"))
    end

    test "start_publisher/3, wrong topic name" do
      assert {:error, _} = Rclex.start_publisher(StdMsgs.Msg.String, "chatter", "name")
    end

    test "stop_publisher/3" do
      :ok = Rclex.start_publisher(StdMsgs.Msg.String, "/chatter", "name")

      assert capture_log(fn ->
               :ok = Rclex.stop_publisher(StdMsgs.Msg.String, "/chatter", "name")
             end) =~ "Publisher: :shutdown"

      assert {:error, :not_found} = Rclex.stop_publisher(StdMsgs.Msg.String, "/chatter", "name")
    end

    test "stop_publisher/3, node doesn't exist" do
      assert {:noproc, _} =
               catch_exit(Rclex.stop_publisher(StdMsgs.Msg.String, "/chatter", "notexists"))
    end
  end

  describe "subscription" do
    setup do
      :ok = Rclex.start_node("name")
      on_exit(fn -> capture_log(fn -> Rclex.stop_node("name") end) end)

      %{callback: fn _message -> nil end}
    end

    test "start_subscription/4", %{callback: callback} do
      assert :ok = Rclex.start_subscription(callback, StdMsgs.Msg.String, "/chatter", "name")

      assert {:error, :already_started} =
               Rclex.start_subscription(callback, StdMsgs.Msg.String, "/chatter", "name")
    end

    test "start_subscription/4, node doesn't exist", %{callback: callback} do
      assert {:noproc, _} =
               catch_exit(
                 Rclex.start_subscription(callback, StdMsgs.Msg.String, "/chatter", "notexists")
               )
    end

    test "start_subscription/4, wrong topic name", %{callback: callback} do
      assert {:error, _} =
               Rclex.start_subscription(callback, StdMsgs.Msg.String, "chatter", "name")
    end

    test "stop_subscription/3", %{callback: callback} do
      :ok = Rclex.start_subscription(callback, StdMsgs.Msg.String, "/chatter", "name")

      assert capture_log(fn ->
               :ok = Rclex.stop_subscription(StdMsgs.Msg.String, "/chatter", "name")
             end) =~ "Subscription: :shutdown"

      assert {:error, :not_found} =
               Rclex.stop_subscription(StdMsgs.Msg.String, "/chatter", "name")
    end

    test "stop_subscription/3, node doesn't exist", %{callback: _callback} do
      assert {:noproc, _} =
               catch_exit(Rclex.stop_subscription(StdMsgs.Msg.String, "/chatter", "notexists"))
    end
  end

  describe "pub/sub" do
    setup do
      name = "name"
      topic_name = "/chatter"

      :ok = Rclex.start_node(name)

      me = self()
      :ok = Rclex.start_subscription(&send(me, &1), StdMsgs.Msg.String, topic_name, name)
      :ok = Rclex.start_publisher(StdMsgs.Msg.String, topic_name, name)

      on_exit(fn -> capture_log(fn -> Rclex.stop_node(name) end) end)

      %{topic_name: topic_name, name: name}
    end

    test "publish/3", %{topic_name: topic_name, name: name} do
      for i <- 1..100 do
        message = struct(StdMsgs.Msg.String, %{data: "publish #{i}"})
        assert Rclex.publish(message, topic_name, name) == :ok
        assert_receive ^message
      end
    end
  end

  describe "service" do
    setup do
      :ok = Rclex.start_node("name")
      on_exit(fn -> capture_log(fn -> Rclex.stop_node("name") end) end)

      %{
        callback: fn %StdSrvs.Srv.SetBool.Request{data: data} ->
          %StdSrvs.Srv.SetBool.Response{success: data}
        end
      }
    end

    test "start_service/4", %{callback: callback} do
      assert :ok = Rclex.start_service(callback, StdSrvs.Srv.SetBool, "/set_test_bool", "name")

      assert {:error, :already_started} =
               Rclex.start_service(callback, StdSrvs.Srv.SetBool, "/set_test_bool", "name")
    end

    test "start_service/4, node doesn't exist", %{callback: callback} do
      assert {:noproc, _} =
               catch_exit(
                 Rclex.start_service(callback, StdSrvs.Srv.SetBool, "/set_test_bool", "notexists")
               )
    end

    test "start_service/4, wrong service name", %{callback: callback} do
      assert {:error, _} =
               Rclex.start_service(callback, StdSrvs.Srv.SetBool, "set_test_bool", "name")
    end

    test "stop_service/3", %{callback: callback} do
      :ok = Rclex.start_service(callback, StdSrvs.Srv.SetBool, "/set_test_bool", "name")

      assert capture_log(fn ->
               :ok = Rclex.stop_service(StdSrvs.Srv.SetBool, "/set_test_bool", "name")
             end) =~ "Service: :shutdown"

      assert {:error, :not_found} =
               Rclex.stop_service(StdSrvs.Srv.SetBool, "/set_test_bool", "name")
    end

    test "stop_service/3, node doesn't exist", %{callback: _callback} do
      assert {:noproc, _} =
               catch_exit(Rclex.stop_service(StdSrvs.Srv.SetBool, "/chatter", "notexists"))
    end
  end

  describe "client" do
    setup do
      :ok = Rclex.start_node("name")
      on_exit(fn -> capture_log(fn -> Rclex.stop_node("name") end) end)

      %{
        callback: fn _request, _response ->
          nil
        end
      }
    end

    test "start_client/4", %{callback: callback} do
      assert :ok = Rclex.start_client(callback, StdSrvs.Srv.SetBool, "/set_test_bool", "name")

      assert {:error, :already_started} =
               Rclex.start_client(callback, StdSrvs.Srv.SetBool, "/set_test_bool", "name")
    end

    test "start_client/4, node doesn't exist", %{callback: callback} do
      assert {:noproc, _} =
               catch_exit(
                 Rclex.start_client(callback, StdSrvs.Srv.SetBool, "/set_test_bool", "notexists")
               )
    end

    test "start_client/4, wrong client name", %{callback: callback} do
      assert {:error, _} =
               Rclex.start_client(callback, StdSrvs.Srv.SetBool, "set_test_bool", "name")
    end

    test "stop_client/3", %{callback: callback} do
      :ok = Rclex.start_client(callback, StdSrvs.Srv.SetBool, "/set_test_bool", "name")

      assert capture_log(fn ->
               :ok = Rclex.stop_client(StdSrvs.Srv.SetBool, "/set_test_bool", "name")
             end) =~ "Client: :shutdown"

      assert {:error, :not_found} =
               Rclex.stop_client(StdSrvs.Srv.SetBool, "/set_test_bool", "name")
    end

    test "stop_client/3, node doesn't exist", %{callback: _callback} do
      assert {:noproc, _} =
               catch_exit(Rclex.stop_client(StdSrvs.Srv.SetBool, "/chatter", "notexists"))
    end
  end

  describe "calling services" do
    setup do
      name = "name"
      service_name = "/set_test_bool"

      :ok = Rclex.start_node(name)

      service_callback = fn %RclInterfaces.Srv.GetParameterTypes.Request{names: names} ->
        %RclInterfaces.Srv.GetParameterTypes.Response{
          types: Enum.map_join(names, fn n -> String.length(to_string(n)) end)
        }
      end

      me = self()

      receive_callback = fn _request, response ->
        send(me, response)
      end

      :ok =
        Rclex.start_service(
          service_callback,
          RclInterfaces.Srv.GetParameterTypes,
          service_name,
          name
        )

      :ok =
        Rclex.start_client(
          receive_callback,
          RclInterfaces.Srv.GetParameterTypes,
          service_name,
          name
        )

      on_exit(fn -> capture_log(fn -> Rclex.stop_node(name) end) end)

      %{
        name: name,
        service_name: service_name
      }
    end

    test "call_async/4", %{service_name: service_name, name: name} do
      request = struct(RclInterfaces.Srv.GetParameterTypes.Request, %{names: ["test"]})
      assert Rclex.call_async(request, "does_not_exist", name) == {:error, :not_found}

      for i <- 1..10 do
        names = Enum.map(0..i, fn _ -> "abc" end)
        request = struct(RclInterfaces.Srv.GetParameterTypes.Request, %{names: names})

        response =
          struct(RclInterfaces.Srv.GetParameterTypes.Response, %{
            types: Enum.map_join(names, fn n -> String.length(to_string(n)) end)
          })

        assert Rclex.call_async(request, service_name, name) == :ok
        assert_receive ^response
      end
    end

    test "call_timeout/5", %{service_name: service_name, name: name} do
      request = struct(RclInterfaces.Srv.GetParameterTypes.Request, %{names: ["test"]})
      # not found returns error tuple
      assert Rclex.call_timeout(request, "does_not_exist", name, 0.1) == {:error, :not_found}

      # success within timeout
      response =
        struct(RclInterfaces.Srv.GetParameterTypes.Response, %{
          types: Enum.map_join(["test"], fn n -> String.length(to_string(n)) end)
        })

      assert Rclex.call_timeout(request, service_name, name, 1.0) == {:ok, response}

      # create slow service to trigger timeout
      slow_name = service_name <> "_slow"

      slow_callback = fn _req ->
        Process.sleep(200)
        %RclInterfaces.Srv.GetParameterTypes.Response{types: ""}
      end

      :ok =
        Rclex.start_service(
          slow_callback,
          RclInterfaces.Srv.GetParameterTypes,
          slow_name,
          name
        )

      receive_callback = fn _req, resp -> send(self(), resp) end

      :ok =
        Rclex.start_client(
          receive_callback,
          RclInterfaces.Srv.GetParameterTypes,
          slow_name,
          name
        )

      on_exit(fn ->
        capture_log(fn ->
          Rclex.stop_service(RclInterfaces.Srv.GetParameterTypes, slow_name, name)
          Rclex.stop_client(RclInterfaces.Srv.GetParameterTypes, slow_name, name)
        end)
      end)

      assert Rclex.call_timeout(request, slow_name, name, 0.1) == {:error, :timeout}
    end
  end

  describe "action server" do
    setup do
      :ok = Rclex.start_node("name")
      on_exit(fn -> capture_log(fn -> Rclex.stop_node("name") end) end)

      execute_callback = fn %Action.LookupTransform.Goal{
                              target_frame: _target_frame,
                              source_frame: _source_frame
                            },
                            fb_cb ->
        for _i <- 1..10 do
          Process.sleep(200)
          fb_cb.(%Action.LookupTransform.Feedback{})
        end

        %Action.LookupTransform.Result{}
      end

      %{
        action_type: Action.LookupTransform,
        execute_callback: execute_callback
      }
    end

    test "start_action_server/4", %{
      execute_callback: execute_callback,
      action_type: action_type
    } do
      assert :ok =
               Rclex.start_action_server(
                 execute_callback,
                 action_type,
                 "/lookup_transform",
                 "name",
                 goal_callback: fn _req -> :accept end
               )

      # Process.sleep(20000)

      assert {:error, :already_started} =
               Rclex.start_action_server(
                 execute_callback,
                 action_type,
                 "/lookup_transform",
                 "name"
               )
    end

    test "start_action_server/4, node doesn't exist", %{
      execute_callback: execute_callback,
      action_type: action_type
    } do
      assert {:noproc, _} =
               catch_exit(
                 Rclex.start_action_server(
                   execute_callback,
                   action_type,
                   "/lookup_transform",
                   "not_exist"
                 )
               )
    end

    test "start_action_server/4, wrong action name", %{
      execute_callback: execute_callback,
      action_type: action_type
    } do
      assert {:error, _} =
               Rclex.start_action_server(
                 execute_callback,
                 action_type,
                 "rotate_absolute",
                 "name"
               )
    end

    test "stop_action_server/3", %{
      execute_callback: execute_callback,
      action_type: action_type
    } do
      :ok =
        Rclex.start_action_server(
          execute_callback,
          action_type,
          "/lookup_transform",
          "name"
        )

      assert capture_log(fn ->
               :ok = Rclex.stop_action_server(action_type, "/lookup_transform", "name")
             end) =~ "ActionServer: :shutdown"

      assert {:error, :not_found} =
               Rclex.stop_action_server(action_type, "/lookup_transform", "name")
    end

    test "stop_action_server/3, node doesn't exist", %{action_type: action_type} do
      assert {:noproc, _} =
               catch_exit(Rclex.stop_action_server(action_type, "/lookup_transform", "notexists"))
    end
  end

  describe "action client" do
    setup do
      :ok = Rclex.start_node("name")
      on_exit(fn -> capture_log(fn -> Rclex.stop_node("name") end) end)

      %{
        action_type: Action.LookupTransform
      }
    end

    test "start_action_client/3", %{
      action_type: action_type
    } do
      options = Rclex.ActionClientOptions.default()

      assert :ok =
               Rclex.start_action_client(
                 action_type,
                 "/lookup_transform",
                 "name",
                 options: options
               )

      assert {:error, :already_started} =
               Rclex.start_action_client(
                 action_type,
                 "/lookup_transform",
                 "name"
               )
    end

    test "start_action_client/3, node doesn't exist", %{
      action_type: action_type
    } do
      assert {:noproc, _} =
               catch_exit(
                 Rclex.start_action_client(
                   action_type,
                   "/lookup_transform",
                   "not_exist"
                 )
               )
    end

    test "start_action_client/3, wrong action name", %{
      action_type: action_type
    } do
      assert {:error, _} =
               Rclex.start_action_client(
                 action_type,
                 "rotate_absolute",
                 "name"
               )
    end

    test "action_server_available?/3", %{
      action_type: action_type
    } do
      :ok =
        Rclex.start_action_client(
          action_type,
          "/lookup_transform",
          "name"
        )

      assert {:error, :not_found} ==
               Rclex.action_server_available?(action_type, "/does_not_exist", "name")

      assert false == Rclex.action_server_available?(action_type, "/lookup_transform", "name")

      execute_callback = fn %Action.LookupTransform.Goal{}, _fb_cb ->
        %Action.LookupTransform.Result{error: %TF2Error{error: 0, error_string: "no error"}}
      end

      :ok =
        Rclex.start_action_server(
          execute_callback,
          action_type,
          "/lookup_transform",
          "name"
        )

      Process.sleep(10)
      assert true == Rclex.action_server_available?(action_type, "/lookup_transform", "name")

      assert capture_log(fn ->
               :ok = Rclex.stop_action_server(action_type, "/lookup_transform", "name")
             end) =~ "ActionServer: :shutdown"

      assert capture_log(fn ->
               :ok = Rclex.stop_action_client(action_type, "/lookup_transform", "name")
             end) =~ "ActionClient: :shutdown"
    end

    test "stop_action_client/3", %{action_type: action_type} do
      :ok =
        Rclex.start_action_client(
          action_type,
          "/lookup_transform",
          "name"
        )

      assert capture_log(fn ->
               :ok = Rclex.stop_action_client(action_type, "/lookup_transform", "name")
             end) =~ "ActionClient: :shutdown"

      assert {:error, :not_found} =
               Rclex.stop_action_client(action_type, "/lookup_transform", "name")
    end

    test "stop_action_client/3, node doesn't exist", %{action_type: action_type} do
      assert {:noproc, _} =
               catch_exit(Rclex.stop_action_client(action_type, "/lookup_transform", "notexists"))
    end
  end

  describe "setting action goals" do
    setup do
      me = self()

      execute_callback = fn %Action.LookupTransform.Goal{}, publish_feedback ->
        send(me, :started_execute_callback)
        # simulate some work
        for _i <- 1..3 do
          Process.sleep(50)
          feedback = %Action.LookupTransform.Feedback{}
          send(me, :feedback)
          publish_feedback.(feedback)
        end

        send(me, :finished_execute_callback)
        %Action.LookupTransform.Result{error: %TF2Error{error: 4, error_string: "no error"}}
      end

      goal_callback = fn _req ->
        send(me, :goal_callback)
        :accept
      end

      handle_accepted_callback = fn goal_info_struct, action_type, action_name, name, namespace ->
        Rclex.execute_goal(goal_info_struct, action_type, action_name, name, namespace: namespace)
      end

      cancel_callback = fn _goal_info ->
        :accept
      end

      action_type = Action.LookupTransform

      :ok = Rclex.start_node("name")

      status_topic_qos = %Rclex.QoS{
        history: :keep_last,
        depth: 1,
        reliability: :reliable,
        durability: :transient_local,
        deadline: 0.0,
        lifespan: 0.0,
        liveliness: :system_default,
        liveliness_lease_duration: 0.0,
        avoid_ros_namespace_conventions: false
      }

      :ok =
        Rclex.start_action_server(
          execute_callback,
          action_type,
          "/lookup_transform",
          "name",
          goal_callback: goal_callback,
          handle_accepted_callback: handle_accepted_callback,
          cancel_callback: cancel_callback,
          status_topic_qos: status_topic_qos,
          result_timeout: 0.2
        )

      :ok =
        Rclex.start_action_client(
          action_type,
          "/lookup_transform",
          "name"
        )

      on_exit(fn ->
        capture_log(fn ->
          Rclex.stop_action_client(action_type, "/lookup_transform", "name")
          Rclex.stop_action_server(action_type, "/lookup_transform", "name")
          Rclex.stop_node("name")
        end)
      end)

      %{
        action_type: action_type
      }
    end

    test "send_goal_async/3, feedback_callback wrong arity", %{} do
      capture_log(fn ->
        assert_raise RuntimeError, fn ->
          Rclex.send_goal_async(
            %Action.LookupTransform.Goal{
              source_frame: "/source_frame",
              target_frame: "/target_frame"
            },
            "/lookup_transform",
            "name",
            namespace: "/",
            feedback_callback: fn _, _ -> nil end
          )
        end
      end)
    end

    test "send_goal_async/3, action client not found", %{} do
      assert {:error, :not_found} =
               Rclex.send_goal_async(
                 %Action.LookupTransform.Goal{
                   source_frame: "/source_frame",
                   target_frame: "/target_frame"
                 },
                 "/does_not_exist",
                 "name"
               )
    end

    test "send_goal_async/4, uuid exists", %{action_type: action_type} do
      me = self()
      result_callback = fn status, result -> send(me, {:got_result, status, result.error}) end
      accepted_callback = fn uuid, accepted, _time -> send(me, {:accepted, uuid, accepted}) end

      capture_log(fn ->
        assert {:ok, uuid} =
                 Rclex.send_goal_async(
                   %Action.LookupTransform.Goal{
                     source_frame: "/source_frame",
                     target_frame: "/target_frame"
                   },
                   "/lookup_transform",
                   "name",
                   accepted_callback: accepted_callback
                 )

        assert {:ok, second_uuid} =
                 Rclex.send_goal_async(
                   %Action.LookupTransform.Goal{
                     source_frame: "/source_frame",
                     target_frame: "/target_frame"
                   },
                   "/lookup_transform",
                   "name",
                   goal_uuid: uuid,
                   accepted_callback: accepted_callback
                 )

        assert second_uuid == uuid

        assert :ok =
                 Rclex.get_result_async(
                   uuid,
                   result_callback,
                   action_type,
                   "/lookup_transform",
                   "name"
                 )

        assert_receive :goal_callback
        assert_receive {:accepted, ^uuid, true}
        assert_receive {:accepted, ^uuid, false}
        assert_receive :started_execute_callback
        assert_receive :feedback
        assert_receive :feedback
        assert_receive :feedback
        assert_receive :finished_execute_callback
        assert_receive {:got_result, 4, _}
      end)
    end

    test "cancel_goal_async/5, execute_callback gets canceled", %{action_type: action_type} do
      me = self()
      result_callback = fn status, result -> send(me, {:got_result, status, result.error}) end

      cancel_callback = fn return_code, goals_canceling ->
        send(me, {:canceled, return_code, goals_canceling})
      end

      capture_log(fn ->
        for _i <- 0..3 do
          assert {:ok, uuid} =
                   Rclex.send_goal_async(
                     %Action.LookupTransform.Goal{
                       source_frame: "/source_frame",
                       target_frame: "/target_frame"
                     },
                     "/lookup_transform",
                     "name"
                   )

          assert :ok =
                   Rclex.get_result_async(
                     uuid,
                     result_callback,
                     action_type,
                     "/lookup_transform",
                     "name"
                   )

          Process.sleep(60)

          assert :ok =
                   Rclex.cancel_goal_async(
                     uuid,
                     cancel_callback,
                     action_type,
                     "/lookup_transform",
                     "name"
                   )

          assert_receive :goal_callback
          assert_receive :started_execute_callback
          assert_receive :feedback
          assert_receive {:canceled, 0, _}
          refute_receive :finished_execute_callback
          assert_receive {:got_result, 5, _}
        end
      end)
    end

    test "cancel_goal_async/5, wrong arity for cancel_callback", %{action_type: action_type} do
      cancel_callback = fn _something, _return_code, _goals_canceling ->
        nil
      end

      capture_log(fn ->
        assert {:ok, uuid} =
                 Rclex.send_goal_async(
                   %Action.LookupTransform.Goal{
                     source_frame: "/source_frame",
                     target_frame: "/target_frame"
                   },
                   "/lookup_transform",
                   "name"
                 )

        assert_raise RuntimeError, fn ->
          Rclex.cancel_goal_async(
            uuid,
            cancel_callback,
            action_type,
            "/lookup_transform",
            "name"
          )
        end
      end)
    end

    test "cancel_goal_async/5, action client not found", %{action_type: action_type} do
      cancel_callback = fn _return_code, _goals_canceling ->
        nil
      end

      capture_log(fn ->
        assert {:ok, uuid} =
                 Rclex.send_goal_async(
                   %Action.LookupTransform.Goal{
                     source_frame: "/source_frame",
                     target_frame: "/target_frame"
                   },
                   "/lookup_transform",
                   "name"
                 )

        assert {:error, :not_found} =
                 Rclex.cancel_goal_async(
                   uuid,
                   cancel_callback,
                   action_type,
                   "/does_not_exist",
                   "name"
                 )
      end)
    end

    test "get_result_async/5, execute_callback receives result", %{action_type: action_type} do
      me = self()
      result_callback = fn status, result -> send(me, {:got_result, status, result.error}) end

      capture_log(fn ->
        for _i <- 0..3 do
          assert {:ok, uuid} =
                   Rclex.send_goal_async(
                     %Action.LookupTransform.Goal{
                       source_frame: "/source_frame",
                       target_frame: "/target_frame"
                     },
                     "/lookup_transform",
                     "name"
                   )

          assert :ok =
                   Rclex.get_result_async(
                     uuid,
                     result_callback,
                     action_type,
                     "/lookup_transform",
                     "name"
                   )

          assert_receive :goal_callback
          assert_receive :started_execute_callback
          assert_receive :feedback
          assert_receive :feedback
          assert_receive :feedback
          assert_receive :finished_execute_callback

          assert_receive {:got_result, 4,
                          %Rclex.Pkgs.Tf2Msgs.Msg.TF2Error{error: 4, error_string: "no error"}}
        end
      end)
    end

    test "get_result_async/5, result_callback with wrong arity", %{action_type: action_type} do
      result_callback = fn _something, _status, _result -> nil end

      capture_log(fn ->
        assert {:ok, uuid} =
                 Rclex.send_goal_async(
                   %Action.LookupTransform.Goal{
                     source_frame: "/source_frame",
                     target_frame: "/target_frame"
                   },
                   "/lookup_transform",
                   "name"
                 )

        assert_raise RuntimeError, fn ->
          Rclex.get_result_async(
            uuid,
            result_callback,
            action_type,
            "/lookup_transform",
            "name"
          )
        end
      end)
    end

    test "get_result_async/5, action client not found", %{action_type: action_type} do
      result_callback = fn _status, _result -> nil end

      capture_log(fn ->
        assert {:ok, uuid} =
                 Rclex.send_goal_async(
                   %Action.LookupTransform.Goal{
                     source_frame: "/source_frame",
                     target_frame: "/target_frame"
                   },
                   "/lookup_transform",
                   "name"
                 )

        assert {:error, :not_found} =
                 Rclex.get_result_async(
                   uuid,
                   result_callback,
                   action_type,
                   "/does_not_exist",
                   "name"
                 )
      end)
    end
  end

  describe "raising action goal execution" do
    setup do
      me = self()

      raising_execute_callback = fn %Action.LookupTransform.Goal{
                                      source_frame: _source_frame,
                                      target_frame: _target_frame
                                    },
                                    _fb_cb ->
        send(me, :execute_callback)
        Process.sleep(50)
        raise("test raise")
        send(me, :finished_execute_callback)
        %Action.LookupTransform.Result{}
      end

      goal_callback = fn _req ->
        send(me, :goal_callback)
        :accept
      end

      handle_accepted_callback = fn goal_info_struct, action_type, action_name, name, namespace ->
        Rclex.execute_goal(goal_info_struct, action_type, action_name, name, namespace: namespace)
      end

      action_type = Action.LookupTransform

      :ok = Rclex.start_node("name")

      :ok =
        Rclex.start_action_server(
          raising_execute_callback,
          action_type,
          "/lookup_transform",
          "name",
          goal_callback: goal_callback,
          handle_accepted_callback: handle_accepted_callback
        )

      :ok =
        Rclex.start_action_client(
          action_type,
          "/lookup_transform",
          "name"
        )

      on_exit(fn ->
        capture_log(fn ->
          Rclex.stop_action_server(action_type, "/lookup_transform", "name")
          Rclex.stop_action_client(action_type, "/lookup_transform", "name")
          Rclex.stop_node("name")
        end)
      end)

      %{
        action_type: action_type
      }
    end

    test "send_goal_async/3, execute_callback raises", %{action_type: action_type} do
      me = self()
      result_callback = fn status, result -> send(me, {:got_result, status, result.error}) end

      capture_log(fn ->
        assert {:ok, uuid} =
                 Rclex.send_goal_async(
                   %Action.LookupTransform.Goal{
                     target_frame: "base_link",
                     source_frame: "camera_link"
                   },
                   "/lookup_transform",
                   "name"
                 )

        assert :ok =
                 Rclex.get_result_async(
                   uuid,
                   result_callback,
                   action_type,
                   "/lookup_transform",
                   "name"
                 )

        assert_receive :goal_callback
        assert_receive :execute_callback
        assert_receive {:got_result, 6, _}
        refute_receive :finished_execute_callback, 100
      end) =~ "execution failed because of {%RuntimeError{message: \"test raise\"}"
    end

    test "get_result_async/5 for unknown goal", %{action_type: action_type} do
      me = self()
      result_callback = fn status, result -> send(me, {:got_result, status, result.error}) end

      capture_log(fn ->
        uuid = <<1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16>>

        assert :ok =
                 Rclex.get_result_async(
                   uuid,
                   result_callback,
                   action_type,
                   "/lookup_transform",
                   "name"
                 )

        assert_receive {:got_result, 0, _}
      end)
    end
  end

  describe "timer" do
    setup do
      :ok = Rclex.start_node("name")
      on_exit(fn -> capture_log(fn -> Rclex.stop_node("name") end) end)

      %{callback: fn -> nil end}
    end

    test "start_timer/4", %{callback: callback} do
      assert :ok = Rclex.start_timer(10, callback, "timer", "name")
      assert {:error, :already_started} = Rclex.start_timer(10, callback, "timer", "name")
    end

    test "start_timer/4, node doesn't exist", %{callback: callback} do
      assert {:noproc, _} = catch_exit(Rclex.start_timer(10, callback, "timer", "notexists"))
    end

    test "start_timer/4, wrong callback" do
      assert {:error, _} = Rclex.start_timer(10, fn _wrong_args -> nil end, "timer", "name")
    end

    test "stop_timer/3", %{callback: callback} do
      :ok = Rclex.start_timer(100, callback, "timer", "name")

      assert capture_log(fn -> :ok = Rclex.stop_timer("timer", "name") end) =~ "Timer: :shutdown"
      assert {:error, :not_found} = Rclex.stop_timer("timer", "name")
    end

    test "stop_timer/3, node doesn't exist", %{callback: _callback} do
      assert {:noproc, _} = catch_exit(Rclex.stop_timer("timer", "notexists"))
    end
  end

  describe "graph" do
    setup do
      name = "name"
      topic_name = "/chatter"
      service_name = "/get_test_params_types"
      service_type = RclInterfaces.Srv.GetParameterTypes
      action_name = "/lookup_transform"
      action_type = Tf2Msgs.Action.LookupTransform

      :ok = Rclex.start_node("name")
      :ok = Rclex.start_publisher(StdMsgs.Msg.String, topic_name, name)
      :ok = Rclex.start_subscription(fn _msg -> nil end, StdMsgs.Msg.String, topic_name, name)

      service_callback = fn %RclInterfaces.Srv.GetParameterTypes.Request{names: names} ->
        %RclInterfaces.Srv.GetParameterTypes.Response{
          types: Enum.map(names, fn n -> String.length(to_string(n)) end)
        }
      end

      receive_callback = fn _request, _response ->
        nil
      end

      :ok =
        Rclex.start_service(
          service_callback,
          service_type,
          service_name,
          name
        )

      :ok = Rclex.start_client(receive_callback, service_type, service_name, name)

      execute_callback = fn _goal, _feedback_callback ->
        %Tf2Msgs.Action.LookupTransform.Result{}
      end

      :ok = Rclex.start_action_server(execute_callback, action_type, action_name, name)
      :ok = Rclex.start_action_client(action_type, action_name, name)

      on_exit(fn -> capture_log(fn -> Rclex.stop_node("name") end) end)
      :timer.sleep(50)

      %{
        name: name,
        topic_name: topic_name,
        service_type: service_type,
        service_name: service_name,
        action_type: action_type,
        action_name: action_name
      }
    end

    test "count_publishers/2", %{} do
      assert 1 = Rclex.count_publishers("name", "/chatter")
    end

    test "count_subscribers/2", %{name: name, topic_name: topic_name} do
      assert 1 = Rclex.count_subscribers(name, topic_name)
    end

    test "get_client_names_and_types_by_node/4", %{name: name, service_name: service_name} do
      assert Enum.member?(
               Rclex.get_client_names_and_types_by_node(
                 name,
                 name,
                 "/"
               ),
               {service_name, ["rcl_interfaces/srv/GetParameterTypes"]}
             )
    end

    test "get_node_names/2", %{} do
      assert [{"name", "/"}] = Rclex.get_node_names("name")
    end

    test "get_node_names_with_enclaves/2", %{} do
      assert [{"name", "/", "/"}] = Rclex.get_node_names_with_enclaves("name")
    end

    test "get_publisher_names_and_types_by_node/4", %{topic_name: topic_name} do
      assert Enum.member?(
               Rclex.get_publisher_names_and_types_by_node("name", "name", "/"),
               {topic_name, ["std_msgs/msg/String"]}
             )

      assert {:error, :not_found} =
               Rclex.get_publisher_names_and_types_by_node("name", "non_existent", "/")
    end

    test "get_publishers_info_by_topic/3", %{topic_name: topic_name} do
      [info] = Rclex.get_publishers_info_by_topic("name", topic_name)

      assert is_binary(info.endpoint_gid)
      %qos_type{} = info.qos_profile
      assert qos_type == Rclex.QoS

      assert %{
               node_name: "name",
               node_namespace: "/",
               topic_type: "std_msgs/msg/String",
               endpoint_type: :publisher
               # endpoint_gid: <<_gid>>,
               # qos_profile: %Rclex.QoS{...}
             } = Map.drop(info, [:endpoint_gid, :qos_profile])
    end

    test "get_service_names_and_types/2", %{name: name, service_name: service_name} do
      assert Enum.member?(
               Rclex.get_service_names_and_types(name),
               {service_name, ["rcl_interfaces/srv/GetParameterTypes"]}
             )
    end

    test "get_service_names_and_types_by_node/4", %{name: name, service_name: service_name} do
      assert Enum.member?(
               Rclex.get_service_names_and_types_by_node(name, name, "/"),
               {service_name, ["rcl_interfaces/srv/GetParameterTypes"]}
             )
    end

    test "get_subscriber_names_and_types_by_node/4", %{topic_name: topic_name} do
      assert Enum.member?(
               Rclex.get_subscriber_names_and_types_by_node("name", "name", "/"),
               {topic_name, ["std_msgs/msg/String"]}
             )

      assert {:error, :not_found} =
               Rclex.get_subscriber_names_and_types_by_node("name", "non_existent", "/")
    end

    test "get_subscribers_info_by_topic/3", %{topic_name: topic_name} do
      [info] = Rclex.get_subscribers_info_by_topic("name", topic_name)

      assert is_binary(info.endpoint_gid)
      %qos_type{} = info.qos_profile
      assert qos_type == Rclex.QoS

      assert %{
               node_name: "name",
               node_namespace: "/",
               topic_type: "std_msgs/msg/String",
               endpoint_type: :subscription
               # endpoint_gid: <<_gid>>,
               # qos_profile: %Rclex.QoS{...}
             } = Map.drop(info, [:endpoint_gid, :qos_profile])
    end

    test "get_topic_names_and_types/2", %{} do
      assert Enum.member?(
               Rclex.get_topic_names_and_types("name"),
               {"/chatter", ["std_msgs/msg/String"]}
             )
    end

    test "action_get_names_and_types/1", %{} do
      assert [{"/lookup_transform", ["tf2_msgs/action/LookupTransform"]}] =
               Rclex.action_get_names_and_types("name")
    end

    test "action_get_client_names_and_types_by_node/3", %{} do
      assert [{"/lookup_transform", ["tf2_msgs/action/LookupTransform"]}] =
               Rclex.action_get_client_names_and_types_by_node("name", "name", "/")
    end

    test "action_get_server_names_and_types_by_node/3", %{} do
      assert [{"/lookup_transform", ["tf2_msgs/action/LookupTransform"]}] =
               Rclex.action_get_server_names_and_types_by_node("name", "name", "/")
    end

    test "service_server_available?/4", %{
      name: name,
      service_type: service_type,
      service_name: service_name
    } do
      true = Rclex.service_server_available?(service_type, service_name, name)

      {:error, :not_found} =
        Rclex.service_server_available?(service_type, "/does_not_exist", name)
    end
  end

  describe "parameters" do
    setup do
      node_name = "param_test_node"
      namespace = "/test_namespace"
      :ok = Rclex.start_node(node_name)
      :ok = Rclex.start_node(node_name, namespace: namespace)

      on_exit(fn ->
        capture_log(fn ->
          Rclex.stop_node(node_name) && Rclex.stop_node(node_name, namespace: namespace)
        end)
      end)

      %{node_name: node_name, namespace: namespace}
    end

    test "declare_parameter/3 creates new parameter", %{node_name: node_name} do
      assert :ok = Rclex.declare_parameter(node_name, "test_param", default_value: 42)
      assert :ok = Rclex.declare_parameter(node_name, "string_param", default_value: "hello")
      assert :ok = Rclex.declare_parameter(node_name, "bool_param", default_value: true)
    end

    test "declare_parameter/3 with type specification", %{node_name: node_name} do
      assert :ok =
               Rclex.declare_parameter(node_name, "typed_int", type: :integer, default_value: 100)

      assert :ok =
               Rclex.declare_parameter(node_name, "typed_float",
                 type: :float,
                 default_value: 3.14
               )

      assert :ok =
               Rclex.declare_parameter(node_name, "typed_string",
                 type: :string,
                 default_value: "test"
               )

      assert :ok =
               Rclex.declare_parameter(node_name, "typed_bool",
                 type: :boolean,
                 default_value: false
               )
    end

    test "declare_parameter/3 with namespace", %{node_name: node_name, namespace: namespace} do
      assert :ok =
               Rclex.declare_parameter(node_name, "ns_param",
                 default_value: 42,
                 namespace: namespace
               )
    end

    test "declare_parameter/3 with descriptor options", %{node_name: node_name} do
      assert :ok =
               Rclex.declare_parameter(node_name, "described_param",
                 default_value: 50,
                 description: "A test parameter",
                 additional_constraints: "Must be positive",
                 read_only: false
               )
    end

    test "declare_parameter/3 fails when already declared", %{node_name: node_name} do
      assert :ok = Rclex.declare_parameter(node_name, "duplicate_param", default_value: 1)

      assert {:error, :already_declared} =
               Rclex.declare_parameter(node_name, "duplicate_param", default_value: 2)
    end

    test "declare_parameter/3 with array types", %{node_name: node_name} do
      assert :ok =
               Rclex.declare_parameter(node_name, "int_array",
                 type: :integer_array,
                 default_value: [1, 2, 3]
               )

      assert :ok =
               Rclex.declare_parameter(node_name, "float_array",
                 type: :float_array,
                 default_value: [1.1, 2.2]
               )

      assert :ok =
               Rclex.declare_parameter(node_name, "string_array",
                 type: :string_array,
                 default_value: ["a", "b"]
               )

      assert :ok =
               Rclex.declare_parameter(node_name, "bool_array",
                 type: :boolean_array,
                 default_value: [true, false]
               )

      assert :ok =
               Rclex.declare_parameter(node_name, "byte_array",
                 type: :byte_array,
                 default_value: [1, 2, 255]
               )
    end

    test "get_parameter/3 retrieves declared parameter", %{node_name: node_name} do
      assert :ok = Rclex.declare_parameter(node_name, "get_test", default_value: 42)
      assert {:ok, param_value} = Rclex.get_parameter(node_name, "get_test")
      assert param_value.integer_value == 42
    end

    test "get_parameter/3 with different types", %{node_name: node_name} do
      assert :ok = Rclex.declare_parameter(node_name, "int_param", default_value: 123)
      assert :ok = Rclex.declare_parameter(node_name, "str_param", default_value: "hello")
      assert :ok = Rclex.declare_parameter(node_name, "bool_param", default_value: true)
      assert :ok = Rclex.declare_parameter(node_name, "float_param", default_value: 3.14)

      assert {:ok, int_val} = Rclex.get_parameter(node_name, "int_param")
      assert int_val.integer_value == 123

      assert {:ok, str_val} = Rclex.get_parameter(node_name, "str_param")
      assert str_val.string_value == "hello"

      assert {:ok, bool_val} = Rclex.get_parameter(node_name, "bool_param")
      assert bool_val.bool_value == true

      assert {:ok, float_val} = Rclex.get_parameter(node_name, "float_param")
      assert float_val.double_value == 3.14
    end

    test "get_parameter/3 with namespace", %{node_name: node_name, namespace: namespace} do
      assert :ok =
               Rclex.declare_parameter(node_name, "ns_param",
                 default_value: 42,
                 namespace: namespace
               )

      assert {:ok, param_value} = Rclex.get_parameter(node_name, "ns_param", namespace: namespace)
      assert param_value.integer_value == 42
    end

    test "get_parameter/3 fails for undeclared parameter", %{node_name: node_name} do
      assert {:error, :not_declared} = Rclex.get_parameter(node_name, "undeclared_param")
    end

    test "set_parameter/4 updates existing parameter", %{node_name: node_name} do
      assert :ok = Rclex.declare_parameter(node_name, "update_param", default_value: "initial")
      assert :ok = Rclex.set_parameter(node_name, "update_param", "updated")

      assert {:ok, param_value} = Rclex.get_parameter(node_name, "update_param")
      assert param_value.string_value == "updated"
    end

    test "set_parameter/4 with different types", %{node_name: node_name} do
      assert :ok = Rclex.declare_parameter(node_name, "int_param", default_value: 1)
      assert :ok = Rclex.declare_parameter(node_name, "str_param", default_value: "old")
      assert :ok = Rclex.declare_parameter(node_name, "bool_param", default_value: false)

      assert :ok = Rclex.set_parameter(node_name, "int_param", 100)
      assert :ok = Rclex.set_parameter(node_name, "str_param", "new")
      assert :ok = Rclex.set_parameter(node_name, "bool_param", true)

      assert {:ok, int_val} = Rclex.get_parameter(node_name, "int_param")
      assert int_val.integer_value == 100

      assert {:ok, str_val} = Rclex.get_parameter(node_name, "str_param")
      assert str_val.string_value == "new"

      assert {:ok, bool_val} = Rclex.get_parameter(node_name, "bool_param")
      assert bool_val.bool_value == true
    end

    test "set_parameter/4 with namespace", %{node_name: node_name, namespace: namespace} do
      assert :ok =
               Rclex.declare_parameter(node_name, "ns_param",
                 default_value: 1,
                 namespace: namespace
               )

      assert :ok = Rclex.set_parameter(node_name, "ns_param", 100, namespace: namespace)

      assert {:ok, param_value} = Rclex.get_parameter(node_name, "ns_param", namespace: namespace)
      assert param_value.integer_value == 100
    end

    test "set_parameter/4 fails for undeclared parameter", %{node_name: node_name} do
      assert {:error, :not_declared} = Rclex.set_parameter(node_name, "undeclared", 42)
    end

    test "set_parameters/3 updates multiple parameters atomically", %{node_name: node_name} do
      assert :ok = Rclex.declare_parameter(node_name, "param1", default_value: 1)
      assert :ok = Rclex.declare_parameter(node_name, "param2", default_value: "old")

      assert :ok = Rclex.set_parameters(node_name, [{"param1", 10}, {"param2", "new"}])

      assert {:ok, param1_val} = Rclex.get_parameter(node_name, "param1")
      assert param1_val.integer_value == 10

      assert {:ok, param2_val} = Rclex.get_parameter(node_name, "param2")
      assert param2_val.string_value == "new"
    end

    test "set_parameters/3 with namespace", %{node_name: node_name, namespace: namespace} do
      assert :ok =
               Rclex.declare_parameter(node_name, "param1",
                 default_value: 1,
                 namespace: namespace
               )

      assert :ok =
               Rclex.declare_parameter(node_name, "param2",
                 default_value: 2,
                 namespace: namespace
               )

      assert :ok =
               Rclex.set_parameters(node_name, [{"param1", 10}, {"param2", 20}],
                 namespace: namespace
               )

      assert {:ok, param1_val} = Rclex.get_parameter(node_name, "param1", namespace: namespace)
      assert param1_val.integer_value == 10
    end

    test "set_parameters/3 fails when any parameter is undeclared", %{node_name: node_name} do
      assert :ok = Rclex.declare_parameter(node_name, "param1", default_value: 1)

      assert {:error, {:undeclared_parameters, ["undeclared"]}} =
               Rclex.set_parameters(node_name, [{"param1", 10}, {"undeclared", 20}])

      # Verify first parameter was not changed due to atomic operation
      assert {:ok, param1_val} = Rclex.get_parameter(node_name, "param1")
      assert param1_val.integer_value == 1
    end

    test "list_parameters/2 returns all declared parameter names", %{node_name: node_name} do
      # Initially empty
      assert [] = Rclex.list_parameters(node_name)

      # Declare some parameters
      assert :ok = Rclex.declare_parameter(node_name, "param1", default_value: 1)
      assert :ok = Rclex.declare_parameter(node_name, "param2", default_value: "hello")
      assert :ok = Rclex.declare_parameter(node_name, "param3", default_value: true)

      param_names = Rclex.list_parameters(node_name)
      assert length(param_names) == 3
      assert "param1" in param_names
      assert "param2" in param_names
      assert "param3" in param_names
    end

    test "list_parameters/2 with namespace", %{node_name: node_name, namespace: namespace} do
      assert :ok = Rclex.declare_parameter(node_name, "global_param", default_value: 1)

      assert :ok =
               Rclex.declare_parameter(node_name, "ns_param",
                 default_value: 2,
                 namespace: namespace
               )

      global_params = Rclex.list_parameters(node_name)
      assert "global_param" in global_params
      refute "ns_param" in global_params

      ns_params = Rclex.list_parameters(node_name, namespace: namespace)
      assert "ns_param" in ns_params
      refute "global_param" in ns_params
    end

    test "describe_parameters/3 returns parameter descriptors", %{node_name: node_name} do
      assert :ok =
               Rclex.declare_parameter(node_name, "int_param",
                 type: :integer,
                 default_value: 42,
                 description: "Integer parameter"
               )

      assert :ok =
               Rclex.declare_parameter(node_name, "str_param",
                 type: :string,
                 default_value: "hello",
                 description: "String parameter"
               )

      descriptors = Rclex.describe_parameters(node_name, ["int_param", "str_param"])
      assert length(descriptors) == 2

      int_desc = Enum.find(descriptors, &(&1.name == "int_param"))
      str_desc = Enum.find(descriptors, &(&1.name == "str_param"))

      assert int_desc != nil
      assert str_desc != nil
      assert int_desc.description == "Integer parameter"
      assert str_desc.description == "String parameter"
    end

    test "describe_parameters/3 returns all descriptors when no names specified", %{
      node_name: node_name
    } do
      assert :ok = Rclex.declare_parameter(node_name, "param1", default_value: 1)
      assert :ok = Rclex.declare_parameter(node_name, "param2", default_value: 2.5)

      descriptors = Rclex.describe_parameters(node_name)
      assert length(descriptors) == 2

      param_names = Enum.map(descriptors, & &1.name)
      assert "param1" in param_names
      assert "param2" in param_names
    end

    test "describe_parameters/3 with namespace", %{node_name: node_name, namespace: namespace} do
      assert :ok =
               Rclex.declare_parameter(node_name, "ns_param",
                 default_value: 42,
                 namespace: namespace,
                 description: "Namespaced parameter"
               )

      descriptors = Rclex.describe_parameters(node_name, ["ns_param"], namespace: namespace)
      assert length(descriptors) == 1

      [desc] = descriptors
      assert desc.name == "ns_param"
      assert desc.description == "Namespaced parameter"
    end

    test "get_parameter_types/3 returns correct parameter types", %{node_name: node_name} do
      assert :ok =
               Rclex.declare_parameter(node_name, "bool_param",
                 type: :boolean,
                 default_value: true
               )

      assert :ok =
               Rclex.declare_parameter(node_name, "int_param", type: :integer, default_value: 42)

      assert :ok =
               Rclex.declare_parameter(node_name, "float_param",
                 type: :float,
                 default_value: 3.14
               )

      assert :ok =
               Rclex.declare_parameter(node_name, "string_param",
                 type: :string,
                 default_value: "hello"
               )

      assert :ok =
               Rclex.declare_parameter(node_name, "byte_array_param",
                 type: :byte_array,
                 default_value: [1, 2, 3]
               )

      assert :ok =
               Rclex.declare_parameter(node_name, "int_array_param",
                 type: :integer_array,
                 default_value: [100, 200]
               )

      types =
        Rclex.get_parameter_types(node_name, [
          "bool_param",
          "int_param",
          "float_param",
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

    test "get_parameter_types/3 with namespace", %{node_name: node_name, namespace: namespace} do
      assert :ok =
               Rclex.declare_parameter(node_name, "ns_int",
                 type: :integer,
                 default_value: 42,
                 namespace: namespace
               )

      assert :ok =
               Rclex.declare_parameter(node_name, "ns_str",
                 type: :string,
                 default_value: "hello",
                 namespace: namespace
               )

      types = Rclex.get_parameter_types(node_name, ["ns_int", "ns_str"], namespace: namespace)
      assert types == [:integer, :string]
    end

    test "add_parameters_set_callback/3 registers callback for parameter changes", %{
      node_name: node_name
    } do
      test_pid = self()

      callback = fn name, new_value, old_value ->
        send(test_pid, {:param_changed, name, new_value, old_value})
      end

      assert :ok = Rclex.add_parameters_set_callback(node_name, callback)

      # Declare and set parameter to trigger callback
      assert :ok = Rclex.declare_parameter(node_name, "watched_param", default_value: "initial")
      assert :ok = Rclex.set_parameter(node_name, "watched_param", "updated")

      # Should receive callback notification for declaration
      assert_receive {:param_changed, "watched_param", _new_value, nil}, 1000
      # Should receive callback notification for update
      assert_receive {:param_changed, "watched_param", _new_value, _old_value}, 1000
    end

    test "add_parameters_set_callback/3 with namespace", %{
      node_name: node_name,
      namespace: namespace
    } do
      test_pid = self()

      callback = fn name, _new_value, _old_value ->
        send(test_pid, {:param_changed, name})
      end

      assert :ok = Rclex.add_parameters_set_callback(node_name, callback, namespace: namespace)

      # Parameter changes in the namespace should trigger callback
      assert :ok =
               Rclex.declare_parameter(node_name, "ns_param",
                 default_value: 1,
                 namespace: namespace
               )

      assert :ok = Rclex.set_parameter(node_name, "ns_param", 2, namespace: namespace)

      assert_receive {:param_changed, "ns_param"}, 1000
      assert_receive {:param_changed, "ns_param"}, 1000
    end

    test "remove_parameters_set_callback/3 stops parameter change notifications", %{
      node_name: node_name
    } do
      test_pid = self()

      callback = fn name, _new_value, _old_value ->
        send(test_pid, {:param_changed, name})
      end

      # Add and then remove callback
      assert :ok = Rclex.add_parameters_set_callback(node_name, callback)
      assert :ok = Rclex.remove_parameters_set_callback(node_name, callback)

      # Parameter changes should not trigger callback
      assert :ok = Rclex.declare_parameter(node_name, "unwatched_param", default_value: "initial")
      assert :ok = Rclex.set_parameter(node_name, "unwatched_param", "updated")

      # Should not receive callback notifications
      refute_receive {:param_changed, "unwatched_param"}, 100
    end

    test "parameter workflow integration test", %{node_name: node_name} do
      # Declare parameters of different types
      assert :ok =
               Rclex.declare_parameter(node_name, "robot_speed",
                 type: :float,
                 default_value: 1.0,
                 description: "Robot movement speed"
               )

      assert :ok =
               Rclex.declare_parameter(node_name, "robot_name",
                 type: :string,
                 default_value: "R2D2",
                 description: "Robot identifier"
               )

      assert :ok =
               Rclex.declare_parameter(node_name, "sensor_enabled",
                 type: :boolean,
                 default_value: true,
                 description: "Enable sensors"
               )

      assert :ok =
               Rclex.declare_parameter(node_name, "waypoints",
                 type: :integer_array,
                 default_value: [0, 0, 0],
                 description: "Navigation waypoints"
               )

      # List all parameters
      param_names = Rclex.list_parameters(node_name)
      assert length(param_names) == 4
      assert "robot_speed" in param_names
      assert "robot_name" in param_names
      assert "sensor_enabled" in param_names
      assert "waypoints" in param_names

      # Get parameter types
      types = Rclex.get_parameter_types(node_name, param_names)
      assert :float in types
      assert :string in types
      assert :boolean in types
      assert :integer_array in types

      # Get parameter descriptors
      descriptors = Rclex.describe_parameters(node_name, param_names)
      assert length(descriptors) == 4

      speed_desc = Enum.find(descriptors, &(&1.name == "robot_speed"))
      assert speed_desc.description == "Robot movement speed"

      # Update parameters individually
      assert :ok = Rclex.set_parameter(node_name, "robot_speed", 2.5)
      assert :ok = Rclex.set_parameter(node_name, "robot_name", "C3PO")

      # Update parameters atomically
      assert :ok =
               Rclex.set_parameters(node_name, [
                 {"sensor_enabled", false},
                 {"waypoints", [10, 20, 30]}
               ])

      # Verify all updates
      assert {:ok, speed_val} = Rclex.get_parameter(node_name, "robot_speed")
      assert speed_val.double_value == 2.5

      assert {:ok, name_val} = Rclex.get_parameter(node_name, "robot_name")
      assert name_val.string_value == "C3PO"

      assert {:ok, sensor_val} = Rclex.get_parameter(node_name, "sensor_enabled")
      assert sensor_val.bool_value == false

      assert {:ok, waypoints_val} = Rclex.get_parameter(node_name, "waypoints")
      assert waypoints_val.byte_array_value == [10, 20, 30]
    end

    test "parameter edge cases and error handling", %{node_name: node_name} do
      # Test empty parameter name (should be handled gracefully)
      # Note: This might be implementation specific - some ROS2 implementations reject empty names

      # Test parameter name validation
      assert :ok = Rclex.declare_parameter(node_name, "valid_param_123", default_value: 1)
      assert :ok = Rclex.declare_parameter(node_name, "param.with.dots", default_value: 2)
      assert :ok = Rclex.declare_parameter(node_name, "param_with_underscores", default_value: 3)

      # Test large parameter values
      large_string = String.duplicate("a", 1000)
      assert :ok = Rclex.declare_parameter(node_name, "large_string", default_value: large_string)

      large_array = Enum.to_list(1..1000)

      assert :ok =
               Rclex.declare_parameter(node_name, "large_array",
                 type: :integer_array,
                 default_value: large_array
               )

      # Verify large values can be retrieved
      assert {:ok, large_str_val} = Rclex.get_parameter(node_name, "large_string")
      assert String.length(large_str_val.string_value) == 1000

      assert {:ok, large_arr_val} = Rclex.get_parameter(node_name, "large_array")
      assert length(large_arr_val.integer_array_value) == 1000
    end

    test "parameter type consistency and conversion", %{node_name: node_name} do
      # Test that parameters maintain their types correctly
      assert :ok =
               Rclex.declare_parameter(node_name, "zero_int", type: :integer, default_value: 0)

      assert :ok =
               Rclex.declare_parameter(node_name, "zero_float", type: :float, default_value: 0.0)

      assert :ok =
               Rclex.declare_parameter(node_name, "false_bool",
                 type: :boolean,
                 default_value: false
               )

      assert :ok =
               Rclex.declare_parameter(node_name, "empty_string",
                 type: :string,
                 default_value: ""
               )

      # Verify types are preserved
      types =
        Rclex.get_parameter_types(node_name, [
          "zero_int",
          "zero_float",
          "false_bool",
          "empty_string"
        ])

      assert types == [:integer, :float, :boolean, :string]

      # Verify values are preserved correctly
      assert {:ok, int_val} = Rclex.get_parameter(node_name, "zero_int")
      assert int_val.integer_value == 0

      assert {:ok, float_val} = Rclex.get_parameter(node_name, "zero_float")
      assert float_val.double_value == 0.0

      assert {:ok, bool_val} = Rclex.get_parameter(node_name, "false_bool")
      assert bool_val.bool_value == false

      assert {:ok, str_val} = Rclex.get_parameter(node_name, "empty_string")
      assert str_val.string_value == ""
    end
  end
end
