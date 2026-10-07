# == Schema Information
#
# Table name: tasks
#
#  id                   :bigint           not null, primary key
#  completed_at         :datetime
#  due_date             :datetime         not null
#  recurrence_anchor_at :datetime
#  recurrence_interval  :string
#  reminder_sent_at     :datetime
#  title                :string           not null
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  account_id           :bigint           not null
#  assignee_id          :bigint           not null
#  contact_id           :bigint           not null
#  conversation_id      :bigint
#  pipeline_item_id     :bigint
#  recurrence_parent_id :bigint
#
# Indexes
#
#  index_tasks_on_account_id                 (account_id)
#  index_tasks_on_assignee_id                (assignee_id)
#  index_tasks_on_contact_id                 (contact_id)
#  index_tasks_on_conversation_id            (conversation_id)
#  index_tasks_on_due_date_pending_reminder  (due_date) WHERE ((completed_at IS NULL) AND (reminder_sent_at IS NULL))
#  index_tasks_on_pipeline_item_id           (pipeline_item_id)
#  index_tasks_on_recurrence_parent_id       (recurrence_parent_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (assignee_id => users.id)
#  fk_rails_...  (contact_id => contacts.id)
#  fk_rails_...  (conversation_id => conversations.id)
#  fk_rails_...  (pipeline_item_id => pipeline_items.id)
#  fk_rails_...  (recurrence_parent_id => tasks.id)
#
class Task < ApplicationRecord
  belongs_to :account
  belongs_to :contact
  belongs_to :conversation, optional: true
  belongs_to :pipeline_item, optional: true
  belongs_to :assignee, class_name: 'User'
  belongs_to :recurrence_parent, class_name: 'Task', optional: true

  has_many :notifications, as: :primary_actor, dependent: :destroy_async

  RECURRENCE_INTERVALS = %w[daily weekly monthly].freeze

  validates :title, presence: true
  validates :due_date, presence: true
  validates :recurrence_interval, inclusion: { in: RECURRENCE_INTERVALS }, allow_nil: true
  validate :conversation_must_belong_to_contact, if: -> { conversation_id.present? }
  validate :pipeline_item_must_belong_to_contact, if: -> { pipeline_item_id.present? }

  scope :pending, -> { where(completed_at: nil) }

  before_save :reset_reminder_if_rescheduled

  after_create_commit :dispatch_created_event
  after_update_commit :dispatch_completed_event, if: :saved_change_to_completed_at?
  after_update_commit :dispatch_updated_event, if: :broadcast_relevant_change?
  after_update_commit :create_next_occurrence, if: -> { saved_change_to_completed_at? && recurrence_interval.present? }
  # Editing a due date by hand is an explicit "the schedule moved" from the user, unlike merely
  # completing a task late - dropping the anchor makes the chain re-anchor on the new date
  # instead of snapping back to the original grid. before_update, not before_save: on create the
  # due_date is always "changing", and that would wipe the anchor create_next_occurrence just set.
  before_update :reset_recurrence_anchor, if: :will_save_change_to_due_date?
  after_destroy_commit :dispatch_deleted_event

  def completed?
    completed_at.present?
  end

  # Exposed in email templates through liquid (see ApplicationRecord#droppables) - needed for
  # the task_due mailer (app/mailers/agent_notifications/conversation_notifications_mailer.rb).
  def droppables
    super + ['Task']
  end

  def push_event_data
    {
      id: id,
      title: title,
      due_date: due_date.to_i,
      completed_at: completed_at&.to_i,
      created_at: created_at.to_i,
      updated_at: updated_at.to_i,
      contact_id: contact_id,
      conversation_id: conversation_id,
      pipeline_item_id: pipeline_item_id,
      recurrence_interval: recurrence_interval,
      recurrence_parent_id: recurrence_parent_id,
      assignee: assignee.push_event_data
    }
  end

  private

  def conversation_must_belong_to_contact
    return if conversation&.contact_id == contact_id

    errors.add(:conversation_id, I18n.t('errors.task.conversation_contact_mismatch'))
  end

  def pipeline_item_must_belong_to_contact
    return if pipeline_item&.contact_id == contact_id

    errors.add(:pipeline_item_id, I18n.t('errors.task.pipeline_item_contact_mismatch'))
  end

  def reset_reminder_if_rescheduled
    self.reminder_sent_at = nil if due_date_changed? && reminder_sent_at.present?
  end

  # saved_change_to_completed_at? fires on any change to the column, including it going back
  # to nil when the task is reopened - only spawn the next occurrence when it was actually
  # marked complete, not when reopening it.
  def create_next_occurrence
    return if completed_at.blank?

    account.tasks.create!(
      title: title,
      due_date: next_due_date,
      assignee_id: assignee_id,
      contact_id: contact_id,
      conversation_id: conversation_id,
      pipeline_item_id: pipeline_item_id,
      recurrence_interval: recurrence_interval,
      recurrence_parent_id: id,
      # The root of a chain has no anchor yet, so its own due_date becomes the anchor every
      # later occurrence inherits. Keeping it on the record (rather than walking
      # recurrence_parent_id up to the root) keeps next_due_date a single read - a long-running
      # daily chain would otherwise be thousands of hops deep.
      recurrence_anchor_at: recurrence_anchor_at || due_date
    )
  rescue StandardError => e
    # This runs in after_update_commit, so an exception escapes the controller's update! and
    # turns an already-persisted completion into a 500 - the agent sees an error on an action
    # that, as far as the data goes, worked. The known trigger is a copied pipeline_item_id
    # pointing at a card deleted since this instance was loaded: PipelineItem's
    # `dependent: :nullify` clears the column with a direct UPDATE without touching the Ruby
    # object, so pipeline_item_must_belong_to_contact fails on the new record.
    # Logged with the task id because the bare exception does not carry it, and without it
    # there is no way to tell which recurrence chain stopped.
    Rails.logger.error(
      "[Task] create_next_occurrence: task##{id} completed but the next occurrence could not " \
      "be created (#{e.class}) - the recurrence chain stops here"
    )
    ChatwootExceptionTracker.new(e, account: account).capture_exception
  end

  # Keeps the original grid (a weekly task stays on its weekday) instead of re-anchoring on the
  # completion time, but never hands back an occurrence that is already overdue: steps forward
  # from due_date until it lands in the future. Completing a task 10 days late used to produce a
  # next occurrence 9 days in the past, which either got re-notified immediately or - if it fell
  # outside Tasks::TriggerDueTasksJob's `3.days.ago..Time.current` window - silently stopped
  # notifying forever.
  #
  # Multiplying the step from the anchor rather than adding it to a running value is what keeps a
  # monthly task on its target day: chaining `+= 1.month` would take a Jan 31 task through Feb 28
  # and lose the 31st. The anchor is recurrence_anchor_at, carried unchanged down the whole chain,
  # so the 31st survives any number of short months in between.
  def next_due_date
    step = recurrence_step
    return if step.nil?

    anchor = recurrence_anchor_at || due_date
    # Has to clear the current due_date as well as the present moment: an occurrence completed
    # ahead of time has an anchor older than its own due_date, and stopping at Time.current
    # would hand back the date this very task is already due on.
    floor = [Time.current, due_date].max
    occurrences = 1
    occurrences += 1 while anchor + (step * occurrences) <= floor
    anchor + (step * occurrences)
  end

  def recurrence_step
    case recurrence_interval
    when 'daily' then 1.day
    when 'weekly' then 1.week
    when 'monthly' then 1.month
    end
  end

  def reset_recurrence_anchor
    self.recurrence_anchor_at = nil
  end

  # Mirrors PipelineItem#conversation_must_belong_to_contact (app/models/pipeline_item.rb):
  # avoids a task pointing at a conversation/card from a different contact, which would break
  # the assumption that contact_id is always coherent with the other two.

  # Kept as an explicit list rather than a blanket `saved_changes?`: completed_at has its own
  # event (dispatch_completed_event) and a generic predicate would start broadcasting internal
  # column writes nobody meant to push. These are exactly the fields update_params allows.
  def broadcast_relevant_change?
    saved_change_to_due_date? || saved_change_to_title? ||
      saved_change_to_assignee_id? || saved_change_to_recurrence_interval?
  end

  def dispatch_created_event
    Rails.configuration.dispatcher.dispatch(
      Events::Types::TASK_CREATED, Time.zone.now, task: self, performed_by: Current.executed_by
    )
  end

  def dispatch_updated_event
    Rails.configuration.dispatcher.dispatch(
      Events::Types::TASK_UPDATED, Time.zone.now, task: self, performed_by: Current.executed_by
    )
  end

  def dispatch_completed_event
    Rails.configuration.dispatcher.dispatch(
      Events::Types::TASK_COMPLETED, Time.zone.now, task: self, performed_by: Current.executed_by
    )
  end

  def dispatch_deleted_event
    Rails.configuration.dispatcher.dispatch(
      Events::Types::TASK_DELETED, Time.zone.now,
      task_data: { id: id, account_id: account_id, contact_id: contact_id,
                   conversation_id: conversation_id, pipeline_item_id: pipeline_item_id }
    )
  end
end
