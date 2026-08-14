class Tasks::NotifyDueTaskJob < ApplicationJob
  queue_as :default

  def perform(task)
    return if task.reminder_sent_at.present? || task.completed_at.present?

    NotificationBuilder.new(
      notification_type: 'task_due',
      user: task.assignee,
      account: task.account,
      primary_actor: task
    ).perform

    # rubocop:disable Rails/SkipsModelValidations
    task.update_column(:reminder_sent_at, Time.zone.now)
    # rubocop:enable Rails/SkipsModelValidations
  end
end
