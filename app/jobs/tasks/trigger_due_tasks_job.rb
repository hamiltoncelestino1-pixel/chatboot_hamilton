class Tasks::TriggerDueTasksJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    Task.where(reminder_sent_at: nil, completed_at: nil)
        .where(due_date: 3.days.ago..Time.current)
        .find_each(batch_size: 100) do |task|
      # rubocop:disable Rails/SkipsModelValidations
      # Claim before enqueueing: if the cron fires again before NotifyDueTaskJob runs, the
      # WHERE reminder_sent_at: nil above no longer matches this task, so it won't be
      # re-enqueued and double-notified.
      next unless task.update_column(:reminder_sent_at, Time.zone.now)
      # rubocop:enable Rails/SkipsModelValidations

      Tasks::NotifyDueTaskJob.perform_later(task)
    end
  end
end
