# Mirrors assignee_id/team_id bidirectionally between a PipelineItem and its linked
# Conversation, gated by Pipeline#sync_assignments. Anti-loop guard is convergence by value
# (only write when the target differs from the source) rather than a Current-based flag,
# since this runs inside EventDispatcherJob - a Current thread-local set before the write
# would not survive into the follow-up job that reacts to the resulting event.
class Pipelines::AssignmentSyncService
  include PipelineItemActions

  def sync_from_pipeline_item(pipeline_item, changed_attributes)
    return unless relevant_change?(changed_attributes)
    return if pipeline_item.conversation_id.blank?
    return unless pipeline_item.pipeline&.sync_assignments?

    conversation = pipeline_item.conversation
    return if conversation.blank?

    updates = conversation_updates_from_pipeline_item(pipeline_item, conversation, changed_attributes)
    apply_updates(conversation, updates)
  end

  def sync_from_conversation(conversation, changed_attributes)
    return unless relevant_change?(changed_attributes)

    linked_items(conversation).each do |item|
      sync_item_from_conversation(item, conversation, changed_attributes)
    end
  end

  private

  def relevant_change?(changed_attributes)
    changed_attributes.present? && changed_attributes.keys.intersect?(%w[assignee_id team_id])
  end

  def apply_updates(record, updates)
    return if updates.blank?

    record.update!(updates)
  end

  def conversation_updates_from_pipeline_item(pipeline_item, conversation, changed_attributes)
    updates = {}
    if changed_attributes.key?('assignee_id') && conversation.assignee_id != pipeline_item.assignee_id
      updates[:assignee_id] = pipeline_item.assignee_id
    end
    updates[:team_id] = pipeline_item.team_id if changed_attributes.key?('team_id') && conversation.team_id != pipeline_item.team_id
    updates
  end

  # conversation_id is not unique on pipeline_items - the same conversation can be linked to
  # cards in different pipelines (uniqueness is contact_id scoped to pipeline_id), so every
  # eligible linked item needs to be synced, not just one.
  def linked_items(conversation)
    PipelineItem.where(
      conversation_id: conversation.id,
      pipeline_id: Pipeline.where(account_id: conversation.account_id, sync_assignments: true).select(:id)
    )
  end

  def sync_item_from_conversation(item, conversation, changed_attributes)
    updates = assignee_update_from_conversation(item, conversation, changed_attributes)
              .merge(team_update_from_conversation(item, conversation, changed_attributes))
    apply_updates(item, updates)
  end

  # A conversation's assignee can be any account user, with no notion of "pipeline member" -
  # unlike team_belongs_to_account? (PipelineItemActions), there's no existing guard to reuse
  # here, and PipelineItem#assignee_must_be_pipeline_member would otherwise raise
  # RecordInvalid on the common case of a conversation assigned to a non-pipeline-member.
  def assignee_update_from_conversation(item, conversation, changed_attributes)
    return {} unless changed_attributes.key?('assignee_id')
    return {} if item.assignee_id == conversation.assignee_id

    unless assignee_eligible?(item, conversation.assignee_id)
      log_ineligible_assignee(item, conversation.assignee_id)
      return {}
    end

    { assignee_id: conversation.assignee_id }
  end

  def team_update_from_conversation(item, conversation, changed_attributes)
    return {} unless changed_attributes.key?('team_id')
    return {} if item.team_id == conversation.team_id

    unless conversation.team_id.blank? || team_belongs_to_account?(item, conversation.team_id)
      log_invalid_team(item, conversation.team_id)
      return {}
    end

    { team_id: conversation.team_id }
  end

  def assignee_eligible?(pipeline_item, assignee_id)
    return true if assignee_id.blank?

    assignee = User.find_by(id: assignee_id)
    return false if assignee.blank?

    assignee.administrator? || pipeline_item.pipeline.members.exists?(id: assignee_id)
  end

  def log_ineligible_assignee(pipeline_item, assignee_id)
    Rails.logger.info(
      "[Pipelines::AssignmentSyncService] assignee_id=#{assignee_id} is not eligible for " \
      "pipeline_item_id=#{pipeline_item.id} (not an admin nor a pipeline member), skipping sync"
    )
  end
end
