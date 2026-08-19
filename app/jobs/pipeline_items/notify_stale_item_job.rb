class PipelineItems::NotifyStaleItemJob < ApplicationJob
  queue_as :default

  def perform(pipeline_item)
    # PipelineItem#assignee is optional, unlike Task#assignee - the trigger job already
    # filters these out, but guard here too in case this job is ever enqueued directly.
    return if pipeline_item.assignee.blank?

    NotificationBuilder.new(
      notification_type: 'pipeline_item_stale',
      user: pipeline_item.assignee,
      account: pipeline_item.account,
      primary_actor: pipeline_item
    ).perform
  end
end
