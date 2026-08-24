defmodule Rclex.TypeDescriptionModules do
  @moduledoc false

  def message_module(name) when is_binary(name) do
    Module.concat([Rclex, Pkgs, TypeDescriptionInterfaces, Msg, String.to_atom(name)])
  end

  def service_module(name) when is_binary(name) do
    Module.concat([Rclex, Pkgs, TypeDescriptionInterfaces, Srv, String.to_atom(name)])
  end

  def request_module(service_name) when is_binary(service_name) do
    Module.concat(service_module(service_name), Request)
  end

  def response_module(service_name) when is_binary(service_name) do
    Module.concat(service_module(service_name), Response)
  end

  def new(module, fields) when is_atom(module) and is_map(fields) do
    struct(module, fields)
  end

  def call(module, function, arguments) when is_atom(module) and is_atom(function) do
    apply(module, function, arguments)
  end
end
