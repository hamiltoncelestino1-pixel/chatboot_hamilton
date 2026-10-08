# Does not inherit ActionService: that base class is 100% coupled to @conversation
# (app/services/action_service.rb), which doesn't apply here - a pipeline macro runs
# directly against a PipelineItem, with no conversation involved.
class Macros::PipelineExecutionService
  include PipelineItemActions

  def initialize(macro, pipeline_item, user)
    @macro = macro
    @pipeline_item = pipeline_item
    @account = macro.account
    @user = user
    Current.user = user
  end

  def perform
    @macro.actions.each do |action|
      # Reload before every action: a failed update! in the previous iteration leaves
      # invalid attributes assigned in memory (never reverted), which would otherwise
      # make the next action's own update! spuriously fail the same validation.
      @pipeline_item.reload
      action = action.with_indifferent_access
      begin
        send(action[:action_name], @pipeline_item, action[:action_params])
      rescue StandardError => e
        ChatwootExceptionTracker.new(e, account: @account).capture_exception
      end
    end
  ensure
    Current.reset
  end

  private

  def move_pipeline_item_stage(pipeline_item, params)
    params = params[0]
    target_stage = move_stage(pipeline_item, params[:target_stage_id], params[:pipeline_lost_reason_id])
    log_invalid_target_stage(pipeline_item, params[:target_stage_id]) if target_stage.blank?
  end

  def assign_pipeline_item_agent(pipeline_item, params)
    params = params[0]
    assign_pipeline_agent(pipeline_item, resolve_assignee_mode(params[:assignee_mode]))
  end

  def assign_pipeline_item_team(pipeline_item, params)
    params = params[0]
    assign_pipeline_team(pipeline_item, resolve_team_mode(params[:team_mode]))
  end

  def add_pipeline_item_label(pipeline_item, params)
    params = params[0]
    add_pipeline_label(pipeline_item, Array(params[:labels]))
  end

  def remove_pipeline_item_label(pipeline_item, params)
    params = params[0]
    remove_pipeline_label(pipeline_item, Array(params[:labels]))
  end

  def update_pipeline_item(pipeline_item, params)
    update_fields(pipeline_item, params[0])
  end

  def export_pipeline_item(pipeline_item, params)
    params = params[0]
    target_pipeline = @account.pipelines.find(params[:target_pipeline_id])
    export_to_pipeline(pipeline_item, target_pipeline, params[:target_stage_id])
  end

  def send_webhook_event(pipeline_item, params)
    send_pipeline_webhook_event(pipeline_item, params, 'macro.executed')
  end

  # Conversation-side actions (already implemented and tested in Macros::ExecutionService)
  # delegated onto the card's linked conversation, rather than reimplemented here.
  def send_message(pipeline_item, params)
    delegate_to_conversation(pipeline_item, 'send_message', params)
  end

  def add_label(pipeline_item, params)
    delegate_to_conversation(pipeline_item, 'add_label', params)
  end

  def assign_team(pipeline_item, params)
    delegate_to_conversation(pipeline_item, 'assign_team', params)
  end

  def assign_agent(pipeline_item, params)
    delegate_to_conversation(pipeline_item, 'assign_agent', params)
  end

  def mute_conversation(pipeline_item, params)
    delegate_to_conversation(pipeline_item, 'mute_conversation', params)
  end

  def change_status(pipeline_item, params)
    delegate_to_conversation(pipeline_item, 'change_status', params)
  end

  def remove_label(pipeline_item, params)
    delegate_to_conversation(pipeline_item, 'remove_label', params)
  end

  def remove_assigned_agent(pipeline_item, params)
    delegate_to_conversation(pipeline_item, 'remove_assigned_agent', params)
  end

  def remove_assigned_team(pipeline_item, params)
    delegate_to_conversation(pipeline_item, 'remove_assigned_team', params)
  end

  def resolve_conversation(pipeline_item, params)
    delegate_to_conversation(pipeline_item, 'resolve_conversation', params)
  end

  def snooze_conversation(pipeline_item, params)
    delegate_to_conversation(pipeline_item, 'snooze_conversation', params)
  end

  def change_priority(pipeline_item, params)
    delegate_to_conversation(pipeline_item, 'change_priority', params)
  end

  def send_email_transcript(pipeline_item, params)
    delegate_to_conversation(pipeline_item, 'send_email_transcript', params)
  end

  def send_attachment(pipeline_item, params)
    delegate_to_conversation(pipeline_item, 'send_attachment', params)
  end

  def add_private_note(pipeline_item, params)
    delegate_to_conversation(pipeline_item, 'add_private_note', params)
  end

  def delegate_to_conversation(pipeline_item, action_name, params)
    conversation = pipeline_item.conversation
    return log_no_conversation(pipeline_item, action_name) if conversation.blank?

    Macros::ExecutionService.new(@macro, conversation, @user).send(action_name, params)
  end

  def log_no_conversation(pipeline_item, action_name)
    Rails.logger.info(
      "[Macros::PipelineExecutionService] #{action_name}: pipeline_item##{pipeline_item.id} has no linked conversation, skipping"
    )
  end

  def log_invalid_target_stage(pipeline_item, target_stage_id)
    Rails.logger.info(
      "[Macros::PipelineExecutionService] target_stage_id=#{target_stage_id} does not belong to " \
      "pipeline_item##{pipeline_item.id}'s pipeline (pipeline_id=#{pipeline_item.pipeline_id})"
    )
  end
end
