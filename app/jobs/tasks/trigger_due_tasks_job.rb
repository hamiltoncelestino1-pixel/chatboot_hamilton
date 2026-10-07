class Tasks::TriggerDueTasksJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    Task.where(reminder_sent_at: nil, completed_at: nil)
        .where(due_date: 3.days.ago..Time.current)
        .find_each(batch_size: 100) do |task|
      # rubocop:disable Rails/SkipsModelValidations
      # Claim before enqueueing, and conditionally: carrying `reminder_sent_at IS NULL` in the
      # WHERE makes this a real compare-and-swap, so two overlapping runs of this job that both
      # read the row before either commits still produce exactly one winner. update_all returns
      # the number of rows it touched - 0 means someone else claimed it first, so skip.
      next unless Task.where(id: task.id, reminder_sent_at: nil)
                      .update_all(reminder_sent_at: Time.zone.now) == 1
      # rubocop:enable Rails/SkipsModelValidations

      Tasks::NotifyDueTaskJob.perform_later(task)
    end
  end
end
