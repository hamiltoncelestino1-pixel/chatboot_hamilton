class Tasks::NotifyDueTaskJob < ApplicationJob
  queue_as :default

  def perform(task)
    # Tasks::TriggerDueTasksJob claims the task before enqueueing this job, but the default
    # queue can sit on a backlog for a long time. ActiveJob reloads the record through its
    # GlobalID here, so every condition below is re-read at run time rather than trusted from
    # the moment of the claim.
    return if task.completed_at.present?
    # Rescheduled into the future: it is no longer due, and the cron will claim it again when
    # it actually is.
    return if task.due_date > Time.current
    # Rescheduled to a different past date: still overdue, so the check above lets it through,
    # but Task#reset_reminder_if_rescheduled dropped the claim. The cron runs every 5 minutes
    # and will re-claim and notify - without this the agent gets notified twice.
    return if task.reminder_sent_at.blank?

    NotificationBuilder.new(
      notification_type: 'task_due',
      user: task.assignee,
      account: task.account,
      primary_actor: task
    ).perform
  end
end
