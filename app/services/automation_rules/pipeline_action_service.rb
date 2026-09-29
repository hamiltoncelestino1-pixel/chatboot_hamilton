# Handles automation rules triggered by pipeline_item events (task 09 - card created / card
# moved to a stage), as opposed to AutomationRules::ActionService (task 04), which is
# triggered by conversation events and has to resolve the target pipeline_item from a
# contact/pipeline pair. Here the pipeline_item is already the subject of the event, so no
# resolution step or pipeline_id param is needed - action_params carry only what's left
# ambiguous (target stage, assignee/team mode, labels, fields).
class AutomationRules::PipelineActionService
  include PipelineItemActions

  def initialize(rule, account, pipeline_item)
    @rule = rule
    @account = account
    @pipeline_item = pipeline_item
    Current.account = @account
    Current.executed_by = rule
  end

  def perform
    @rule.actions.each do |action|
      # Reload before every action: a failed update! in the previous iteration leaves
      # invalid attributes assigned in memory (never reverted), which would otherwise
      # make the next action's own update! spuriously fail the same validation.
      @pipeline_item.reload
      action = action.with_indifferent_access
      begin
        send(action[:action_name], action[:action_params])
      rescue StandardError => e
        ChatwootExceptionTracker.new(e, account: @account).capture_exception
      end
    end
  ensure
    Current.reset
  end

  private

  def move_pipeline_item_stage(params)
    params = params[0]
    target_stage = move_stage(@pipeline_item, params[:target_stage_id], params[:pipeline_lost_reason_id])
    log_invalid_target_stage(params[:target_stage_id]) if target_stage.blank?
  end

  def assign_pipeline_item_agent(params)
    params = params[0]
    assign_pipeline_agent(@pipeline_item, resolve_assignee_mode(params[:assignee_mode]))
  end

  def assign_pipeline_item_team(params)
    params = params[0]
    assign_pipeline_team(@pipeline_item, resolve_team_mode(params[:team_mode]))
  end

  def add_pipeline_item_label(params)
    params = params[0]
    add_pipeline_label(@pipeline_item, Array(params[:labels]))
  end

  def remove_pipeline_item_label(params)
    params = params[0]
    remove_pipeline_label(@pipeline_item, Array(params[:labels]))
  end

  def update_pipeline_item(params)
    update_fields(@pipeline_item, params[0])
  end

  def export_pipeline_item(params)
    params = params[0]
    target_pipeline = @account.pipelines.find(params[:target_pipeline_id])
    export_to_pipeline(@pipeline_item, target_pipeline, params[:target_stage_id])
  end

  def send_webhook_event(params)
    send_pipeline_webhook_event(@pipeline_item, params, "automation_event.#{@rule.event_name}")
  end

  def create_pipeline_item_task(params)
    params = params[0]
    create_task_for_pipeline_item(@pipeline_item, params)
  end

  def log_invalid_target_stage(target_stage_id)
    Rails.logger.info(
      "[AutomationRules::PipelineActionService] target_stage_id=#{target_stage_id} does not belong to " \
      "pipeline_item##{@pipeline_item.id}'s pipeline (pipeline_id=#{@pipeline_item.pipeline_id})"
    )
  end
end
