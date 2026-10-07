class PipelineItems::TriggerStaleItemsJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    Pipeline.where.not(stale_alert_days: [nil, 0]).find_each do |pipeline|
      stale_items(pipeline).find_each(batch_size: 100) do |item|
        # rubocop:disable Rails/SkipsModelValidations
        # Conditional claim before enqueueing, same compare-and-swap as
        # Tasks::TriggerDueTasksJob: `stale_alert_sent_at IS NULL` lives in the WHERE, so
        # overlapping runs can't both claim the same card and double-notify it.
        next unless PipelineItem.where(id: item.id, stale_alert_sent_at: nil)
                                .update_all(stale_alert_sent_at: Time.zone.now) == 1
        # rubocop:enable Rails/SkipsModelValidations

        PipelineItems::NotifyStaleItemJob.perform_later(item)
      end
    end
  end

  private

  def stale_items(pipeline)
    pipeline.pipeline_items
            .joins(:pipeline_stage)
            .where.not(pipeline_stages: { stage_type: [:won, :lost] })
            .where(stale_alert_sent_at: nil)
            # Cards without an assignee are excluded here (not just in the notify job) so they
            # don't get permanently claimed without ever being notified - see them again once
            # they're assigned or the stage changes.
            .where.not(assignee_id: nil)
            .where('stage_changed_at < ?', pipeline.stale_alert_days.days.ago)
  end
end
