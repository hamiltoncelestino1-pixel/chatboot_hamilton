class Tasks::NotifyDueTaskJob < ApplicationJob
  queue_as :default

  def perform(task)
    # reminder_sent_at is already claimed by Tasks::TriggerDueTasksJob before this job is
    # enqueued - only completed_at still needs checking here (task may have been completed
    # in the window between claim and this job running).
    return if task.completed_at.present?

    NotificationBuilder.new(
      notification_type: 'task_due',
      user: task.assignee,
      account: task.account,
      primary_actor: task
    ).perform
  end
end
