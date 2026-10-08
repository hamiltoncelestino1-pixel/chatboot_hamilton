class Notification::RemoveDuplicateNotificationJob < ApplicationJob
  queue_as :default

  def perform(notification)
    return unless notification.is_a?(Notification)

    user_id = notification.user_id
    primary_actor_type = notification.primary_actor_type
    primary_actor_id = notification.primary_actor_id

    # Find older notifications for the same user and the same primary actor. Scoping by type as
    # well as id is what keeps this correct now that PRIMARY_ACTORS has grown beyond Conversation:
    # Conversation, Task and PipelineItem have independent id sequences, so the same number can
    # exist in all three tables, and matching on id alone destroyed unrelated notifications.
    duplicate_notifications = Notification.where(
      user_id: user_id,
      primary_actor_type: primary_actor_type,
      primary_actor_id: primary_actor_id
    ).order(created_at: :desc)

    # Skip the first one (the latest notification) and destroy the rest
    duplicate_notifications.offset(1).each(&:destroy)
  end
end
