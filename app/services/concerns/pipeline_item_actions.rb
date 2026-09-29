# Mutation primitives for a single PipelineItem, shared between
# AutomationRules::ActionService (task 04, resolves the item from a conversation/contact)
# and Macros::PipelineExecutionService (task 06, already has the item as its target).
#
# Deliberately named to avoid ActionService's existing assign_agent/assign_team/add_label/
# remove_label (conversation-level actions) - including this module in a class that inherits
# from ActionService would otherwise silently shadow those with incompatible signatures.
module PipelineItemActions
  def move_stage(pipeline_item, target_stage_id, lost_reason_id = nil)
    target_stage = PipelineStage.find_by(id: target_stage_id, pipeline_id: pipeline_item.pipeline_id)
    return nil if target_stage.blank?

    attrs = { pipeline_stage_id: target_stage.id, position: target_stage.next_position }
    attrs[:pipeline_lost_reason_id] = lost_reason_id if lost_reason_id.present?
    pipeline_item.update!(attrs)
    target_stage
  end

  def assign_pipeline_agent(pipeline_item, assignee_id)
    pipeline_item.update!(assignee_id: assignee_id)
  end

  def assign_pipeline_team(pipeline_item, team_id)
    return log_invalid_team(pipeline_item, team_id) if team_id.present? && !pipeline_team_belongs_to_account?(pipeline_item, team_id)

    pipeline_item.update!(team_id: team_id)
  end

  def add_pipeline_label(pipeline_item, labels)
    return if labels.blank?

    pipeline_item.add_labels(labels)
  end

  def remove_pipeline_label(pipeline_item, labels)
    return if labels.blank?

    pipeline_item.update!(label_list: pipeline_item.label_list - labels)
  end

  def update_fields(pipeline_item, attrs)
    update_attrs = attrs.slice(:title, :value, :notes).compact
    return if update_attrs.blank?

    pipeline_item.update!(update_attrs)
  end

  def create_task_for_pipeline_item(pipeline_item, attrs)
    assignee_id = attrs[:assignee_id].presence || pipeline_item.assignee_id
    log_missing_task_assignee(pipeline_item) if assignee_id.blank?

    pipeline_item.account.tasks.create!(
      title: attrs[:title],
      due_date: attrs[:due_in_days].to_i.days.from_now,
      assignee_id: assignee_id,
      contact_id: pipeline_item.contact_id,
      pipeline_item_id: pipeline_item.id
    )
  end

  def export_to_pipeline(pipeline_item, target_pipeline, target_stage_id)
    Pipelines::ExportItemService.new(
      pipeline_item: pipeline_item,
      target_pipeline: target_pipeline,
      target_stage_id: target_stage_id
    ).perform
  end

  # Shared by callers with no conversation to resolve 'conversation_assignee'/'conversation_team'
  # against (Macros::PipelineExecutionService, AutomationRules::PipelineActionService): only
  # 'none'/blank or an explicit id are meaningful here. AutomationRules::ActionService (task 04)
  # keeps its own conversation-aware resolver instead of these, since it needs @conversation.
  def resolve_assignee_mode(assignee_mode)
    return nil if assignee_mode.blank? || assignee_mode == 'none'

    assignee_mode
  end

  def resolve_team_mode(team_mode)
    return nil if team_mode.blank? || team_mode == 'none'

    team_mode
  end

  # Named distinctly from ActionService's own send_webhook_event (see module comment above) -
  # each consumer (AutomationRules::PipelineActionService, Macros::PipelineExecutionService)
  # wraps this with its own event_label, mirroring the conversation-side split between
  # "automation_event.#{@rule.event_name}" and 'macro.executed'.
  def send_pipeline_webhook_event(pipeline_item, url_params, event_label)
    return if url_params.blank? || url_params[0].blank?

    payload = pipeline_item.webhook_data.merge(event: event_label)
    WebhookJob.perform_later(url_params[0], payload)
  end

  private

  # Named distinctly from ActionService's own private team_belongs_to_account?(team_ids) -
  # both are private instance methods, so once a class includes this module alongside
  # inheriting from ActionService (AutomationRules::ActionService, Macros::ExecutionService,
  # task 26), a same-named method here would silently shadow ActionService's version for
  # every implicit-receiver call inside conversation-level actions like #assign_team,
  # regardless of which class the call originates in.
  def pipeline_team_belongs_to_account?(pipeline_item, team_id)
    pipeline_item.account.team_ids.include?(team_id.to_i)
  end

  def log_invalid_team(pipeline_item, team_id)
    Rails.logger.info(
      "[PipelineItemActions] assign_pipeline_team: team_id=#{team_id} does not belong to " \
      "account_id=#{pipeline_item.account_id}, skipping"
    )
  end

  def log_missing_task_assignee(pipeline_item)
    Rails.logger.info(
      '[PipelineItemActions] create_task_for_pipeline_item: no assignee_id given and ' \
      "pipeline_item##{pipeline_item.id} has none either - task creation will fail validation"
    )
  end
end
