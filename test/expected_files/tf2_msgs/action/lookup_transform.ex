defmodule Rclex.Pkgs.Tf2Msgs.Action.LookupTransform do
  @moduledoc false
  @behaviour Rclex.ActionBehaviour

  alias Rclex.Nif

  def type_support!() do
    Nif.tf2_msgs_action_lookup_transform_type_support!()
  end

  def feedback_message_type() do
    Rclex.Pkgs.Tf2Msgs.Action.LookupTransform.FeedbackMessage
  end

  def feedback_type() do
    Rclex.Pkgs.Tf2Msgs.Action.LookupTransform.Feedback
  end

  def goal_type() do
    Rclex.Pkgs.Tf2Msgs.Action.LookupTransform.Goal
  end

  def result_type() do
    Rclex.Pkgs.Tf2Msgs.Action.LookupTransform.Result
  end

  def get_result_request_type() do
    Rclex.Pkgs.Tf2Msgs.Action.LookupTransform.GetResult.Request
  end

  def get_result_response_type() do
    Rclex.Pkgs.Tf2Msgs.Action.LookupTransform.GetResult.Response
  end

  def send_goal_request_type() do
    Rclex.Pkgs.Tf2Msgs.Action.LookupTransform.SendGoal.Request
  end

  def send_goal_response_type() do
    Rclex.Pkgs.Tf2Msgs.Action.LookupTransform.SendGoal.Response
  end
end
