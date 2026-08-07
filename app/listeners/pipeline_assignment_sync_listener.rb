class PipelineAssignmentSyncListener < BaseListener
  def pipeline_item_updated(event)
    pipeline_item = event.data[:pipeline_item]
    changed_attributes = event.data[:changed_attributes]
    return if changed_attributes.blank?

    Pipelines::AssignmentSyncService.new.sync_from_pipeline_item(pipeline_item, changed_attributes)
  end

  def assignee_changed(event)
    sync_from_conversation_event(event)
  end

  def team_changed(event)
    sync_from_conversation_event(event)
  end

  private

  def sync_from_conversation_event(event)
    conversation, = extract_conversation_and_account(event)
    changed_attributes = event.data[:changed_attributes]
    return if changed_attributes.blank?

    Pipelines::AssignmentSyncService.new.sync_from_conversation(conversation, changed_attributes)
  end
end
