# Shared by AutomationRulesController and MacrosController: action_params is either an array
# of scalars (add_label/remove_label labels, send_attachment blob ids) or an array holding a
# single hash (pipeline actions, send_email_to_team) - two shapes under the same key that
# Rails' declarative `permit` can't express in one filter (`action_params: [{}]` strips both
# shapes to empty - see claude/pipeline_tasks/13-fix-strong-params-actions-pipeline.md audit
# notes). This sanitizes each action element according to its actual runtime shape instead.
module PermittedActionParams
  extend ActiveSupport::Concern

  HASH_ACTION_PARAM_FILTER = [
    :pipeline_id, :pipeline_stage_id, :target_stage_id, :target_pipeline_id,
    :assignee_mode, :team_mode, :title, :value, :notes, :message, :pipeline_lost_reason_id,
    { labels: [], team_ids: [] }
  ].freeze

  def permitted_actions(raw_actions)
    return [] if raw_actions.blank?

    raw_actions.map do |action|
      action = ActionController::Parameters.new(action) unless action.is_a?(ActionController::Parameters)
      {
        action_name: action.permit(:action_name)[:action_name],
        action_params: permitted_action_params(action[:action_params])
      }.with_indifferent_access
    end
  end

  private

  def permitted_action_params(raw_params)
    return [] if raw_params.blank?

    first = raw_params.first
    if first.is_a?(ActionController::Parameters)
      [first.permit(*HASH_ACTION_PARAM_FILTER).to_h.with_indifferent_access]
    elsif first.is_a?(Hash)
      [ActionController::Parameters.new(first).permit(*HASH_ACTION_PARAM_FILTER).to_h.with_indifferent_access]
    else
      ActionController::Parameters.new(values: raw_params).permit(values: []).fetch(:values, [])
    end
  end
end
