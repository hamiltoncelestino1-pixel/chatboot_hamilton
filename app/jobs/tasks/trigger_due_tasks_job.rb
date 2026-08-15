class Tasks::TriggerDueTasksJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    Task.where(reminder_sent_at: nil, completed_at: nil)
        .where(due_date: 3.days.ago..Time.current)
        .find_each(batch_size: 100) do |task|
      Tasks::NotifyDueTaskJob.perform_later(task)
    end
  end
end
