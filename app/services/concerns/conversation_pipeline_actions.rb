# Pipeline actions runnable from a conversation context (@account/@conversation ivars),
# shared between AutomationRules::ActionService (task 04) and Macros::ExecutionService
# (task 26) - both resolve the target PipelineItem from the conversation's contact rather
# than already holding it as their execution target (unlike PipelineItemActions).
module ConversationPipelineActions
  def create_pipeline_item(params)
    params = params[0]
    contact = @conversation.contact

    @account.pipeline_items.new(
      contact_id: contact.id,
      conversation_id: @conversation.id,
      pipeline_stage_id: params[:pipeline_stage_id],
      assignee_id: resolve_pipeline_item_assignee_id(params[:assignee_mode]),
      team_id: resolve_pipeline_item_team_id(params[:team_mode]),
      title: params[:title],
      value: params[:value],
      notes: params[:notes]
    ).save!
  end

  def move_pipeline_item_stage(params)
    params = params[0]
    item = resolve_pipeline_item_for_conversation(params[:pipeline_id])
    return log_no_pipeline_item('move_pipeline_item_stage', params[:pipeline_id]) if item.blank?

    target_stage = move_stage(item, params[:target_stage_id])
    log_invalid_target_stage(params[:target_stage_id], item) if target_stage.blank?
  end

  def assign_pipeline_item_agent(params)
    params = params[0]
    item = resolve_pipeline_item_for_conversation(params[:pipeline_id])
    return log_no_pipeline_item('assign_pipeline_item_agent', params[:pipeline_id]) if item.blank?

    assign_pipeline_agent(item, resolve_pipeline_item_assignee_id(params[:assignee_mode]))
  end

  def assign_pipeline_item_team(params)
    params = params[0]
    item = resolve_pipeline_item_for_conversation(params[:pipeline_id])
    return log_no_pipeline_item('assign_pipeline_item_team', params[:pipeline_id]) if item.blank?

    assign_pipeline_team(item, resolve_pipeline_item_team_id(params[:team_mode]))
  end

  def add_pipeline_item_label(params)
    params = params[0]
    item = resolve_pipeline_item_for_conversation(params[:pipeline_id])
    return log_no_pipeline_item('add_pipeline_item_label', params[:pipeline_id]) if item.blank?

    add_pipeline_label(item, Array(params[:labels]))
  end

  def remove_pipeline_item_label(params)
    params = params[0]
    item = resolve_pipeline_item_for_conversation(params[:pipeline_id])
    return log_no_pipeline_item('remove_pipeline_item_label', params[:pipeline_id]) if item.blank?

    remove_pipeline_label(item, Array(params[:labels]))
  end

  def update_pipeline_item(params)
    params = params[0]
    item = resolve_pipeline_item_for_conversation(params[:pipeline_id])
    return log_no_pipeline_item('update_pipeline_item', params[:pipeline_id]) if item.blank?

    update_fields(item, params)
  end

  def export_pipeline_item(params)
    params = params[0]
    item = resolve_pipeline_item_for_conversation(params[:pipeline_id])
    return log_no_pipeline_item('export_pipeline_item', params[:pipeline_id]) if item.blank?

    target_pipeline = @account.pipelines.find(params[:target_pipeline_id])
    export_to_pipeline(item, target_pipeline, params[:target_stage_id])
  end

  private

  def resolve_pipeline_item_for_conversation(pipeline_id)
    @account.pipeline_items.find_by(pipeline_id: pipeline_id, contact_id: @conversation.contact_id)
  end

  def resolve_pipeline_item_assignee_id(assignee_mode)
    return @conversation.assignee_id if assignee_mode == 'conversation_assignee'
    return nil if assignee_mode.blank? || assignee_mode == 'none'

    assignee_mode
  end

  def resolve_pipeline_item_team_id(team_mode)
    return @conversation.team_id if team_mode == 'conversation_team'
    return nil if team_mode.blank? || team_mode == 'none'

    team_mode
  end

  def log_no_pipeline_item(action_name, pipeline_id)
    Rails.logger.info(
      "[ConversationPipelineActions] #{action_name}: no pipeline_item found for pipeline_id=#{pipeline_id}, " \
      "contact_id=#{@conversation.contact_id}"
    )
  end

  def log_invalid_target_stage(target_stage_id, item)
    Rails.logger.info(
      "[ConversationPipelineActions] target_stage_id=#{target_stage_id} does not belong to " \
      "pipeline_item##{item.id}'s pipeline (pipeline_id=#{item.pipeline_id})"
    )
  end
end
