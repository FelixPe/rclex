defmodule Rclex.Pkgs.Turtlesim.Action.RotateAbsolute do
  @moduledoc false
  @behaviour Rclex.ActionBehaviour

  alias Rclex.Nif

  def type_support!() do
    Nif.turtlesim_action_rotate_absolute_type_support!()
  end

  def feedback_message_type() do
    Rclex.Pkgs.Turtlesim.Action.RotateAbsolute.FeedbackMessage
  end

  def feedback_type() do
    Rclex.Pkgs.Turtlesim.Action.RotateAbsolute.Feedback
  end

  def goal_type() do
    Rclex.Pkgs.Turtlesim.Action.RotateAbsolute.Goal
  end

  def result_type() do
    Rclex.Pkgs.Turtlesim.Action.RotateAbsolute.Result
  end

  def get_result_request_type() do
    Rclex.Pkgs.Turtlesim.Action.RotateAbsolute.GetResult.Request
  end

  def get_result_response_type() do
    Rclex.Pkgs.Turtlesim.Action.RotateAbsolute.GetResult.Response
  end

  def send_goal_request_type() do
    Rclex.Pkgs.Turtlesim.Action.RotateAbsolute.SendGoal.Request
  end

  def send_goal_response_type() do
    Rclex.Pkgs.Turtlesim.Action.RotateAbsolute.SendGoal.Response
  end
end
