defmodule Rclex.TypeDescriptionServerTest do
  use ExUnit.Case

  alias Rclex.Pkgs.TypeDescriptionInterfaces.Srv.GetTypeDescription
  alias Rclex.TypeDescriptionServer

  setup do
    :ok = Application.ensure_started(:rclex)

    on_exit(fn ->
      if GenServer.whereis(Rclex.NodeSupervisor.name("type_description_test")) do
        Rclex.stop_node("type_description_test")
      end

      if GenServer.whereis(Rclex.NodeSupervisor.name("type_description_disabled_test")) do
        Rclex.stop_node("type_description_disabled_test")
      end
    end)
  end

  test "returns an unavailable response for an unknown type" do
    request = %{type_name: "missing_msgs/msg/Unknown"}
    response = TypeDescriptionServer.handle_get_type_description(request)

    assert %GetTypeDescription.Response{
             successful: false,
             failure_reason: "type description not available for missing_msgs/msg/Unknown"
           } = response
  end

  test "returns the compiled description for a generated type" do
    response =
      TypeDescriptionServer.handle_get_type_description(%{type_name: "std_msgs/msg/String"})

    assert response.successful
    assert response.type_description.type_description.type_name == "std_msgs/msg/String"

    assert [%{name: "data", type: %{type_id: 17}}] =
             response.type_description.type_description.fields

    assert [%{type_name: "std_msgs/msg/String", encoding: "msg"}] = response.type_sources
  end

  test "omits type sources when the request disables them" do
    response =
      TypeDescriptionServer.handle_get_type_description(%{
        type_name: "std_msgs/msg/String",
        include_type_sources: false
      })

    assert response.successful
    assert response.type_sources == []
  end

  test "accepts a matching compiled type hash" do
    {:ok, type_hash} = Rclex.TypeDescriptionRegistry.fetch_hash("std_msgs/msg/String")

    response =
      TypeDescriptionServer.handle_get_type_description(%{
        type_name: "std_msgs/msg/String",
        type_hash: type_hash
      })

    assert response.successful
    assert response.failure_reason == ""
  end

  test "rejects a mismatched compiled type hash" do
    response =
      TypeDescriptionServer.handle_get_type_description(%{
        type_name: "std_msgs/msg/String",
        type_hash: "RIHS01_0000000000000000000000000000000000000000000000000000000000000000"
      })

    refute response.successful
    assert response.failure_reason == "type hash does not match std_msgs/msg/String"
  end

  test "starts the service by default" do
    assert :ok = Rclex.start_node("type_description_test")

    assert is_pid(GenServer.whereis(TypeDescriptionServer.name("type_description_test")))
  end

  test "does not start the service when disabled" do
    assert :ok =
             Rclex.start_node("type_description_disabled_test",
               type_description_service: false
             )

    assert is_nil(GenServer.whereis(TypeDescriptionServer.name("type_description_disabled_test")))
  end
end
