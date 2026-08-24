defmodule Rclex.TypeDescriptionModulesTest do
  use ExUnit.Case, async: true

  alias Rclex.TypeDescriptionModules

  test "builds type description message and service module names" do
    assert TypeDescriptionModules.message_module("TypeDescription") ==
             Rclex.Pkgs.TypeDescriptionInterfaces.Msg.TypeDescription

    assert TypeDescriptionModules.service_module("GetTypeDescription") ==
             Rclex.Pkgs.TypeDescriptionInterfaces.Srv.GetTypeDescription
  end

  test "builds request and response module names for a service" do
    assert TypeDescriptionModules.request_module("GetTypeDescription") ==
             Rclex.Pkgs.TypeDescriptionInterfaces.Srv.GetTypeDescription.Request

    assert TypeDescriptionModules.response_module("GetTypeDescription") ==
             Rclex.Pkgs.TypeDescriptionInterfaces.Srv.GetTypeDescription.Response
  end

  test "new/2 creates a struct of the requested module" do
    assert %Rclex.Pkgs.TypeDescriptionInterfaces.Msg.Field{name: "field"} =
             TypeDescriptionModules.new(Rclex.Pkgs.TypeDescriptionInterfaces.Msg.Field, %{
               name: "field"
             })
  end

  test "call/3 applies the function on the requested module" do
    assert Rclex.Pkgs.TypeDescriptionInterfaces.Srv.GetTypeDescription.Response ==
             TypeDescriptionModules.call(
               Rclex.Pkgs.TypeDescriptionInterfaces.Srv.GetTypeDescription,
               :response_type,
               []
             )
  end
end
