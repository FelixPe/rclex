defmodule Rclex.ActionServer.GoalSupervisor do
  @moduledoc false

  use DynamicSupervisor

  # callbacks

  def init(_args) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
