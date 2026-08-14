# == Schema Information
#
# Table name: tasks
#
#  id               :bigint           not null, primary key
#  completed_at     :datetime
#  due_date         :datetime         not null
#  reminder_sent_at :datetime
#  title            :string           not null
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  account_id       :bigint           not null
#  assignee_id      :bigint           not null
#  contact_id       :bigint           not null
#  conversation_id  :bigint
#  pipeline_item_id :bigint
#
# Indexes
#
#  index_tasks_on_account_id                 (account_id)
#  index_tasks_on_assignee_id                (assignee_id)
#  index_tasks_on_contact_id                 (contact_id)
#  index_tasks_on_conversation_id            (conversation_id)
#  index_tasks_on_due_date_pending_reminder  (due_date) WHERE ((completed_at IS NULL) AND (reminder_sent_at IS NULL))
#  index_tasks_on_pipeline_item_id           (pipeline_item_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (assignee_id => users.id)
#  fk_rails_...  (contact_id => contacts.id)
#  fk_rails_...  (conversation_id => conversations.id)
#  fk_rails_...  (pipeline_item_id => pipeline_items.id)
#
class Task < ApplicationRecord
  belongs_to :account
  belongs_to :contact
  belongs_to :conversation, optional: true
  belongs_to :pipeline_item, optional: true
  belongs_to :assignee, class_name: 'User'

  has_many :notifications, as: :primary_actor, dependent: :destroy_async

  validates :title, presence: true
  validates :due_date, presence: true
  validate :conversation_must_belong_to_contact, if: -> { conversation_id.present? }
  validate :pipeline_item_must_belong_to_contact, if: -> { pipeline_item_id.present? }

  scope :pending, -> { where(completed_at: nil) }

  before_save :reset_reminder_if_rescheduled

  after_create_commit :dispatch_created_event
  after_update_commit :dispatch_completed_event, if: :saved_change_to_completed_at?
  after_update_commit :dispatch_updated_event, if: :broadcast_relevant_change?
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

  # Mirrors PipelineItem#conversation_must_belong_to_contact (app/models/pipeline_item.rb):
  # avoids a task pointing at a conversation/card from a different contact, which would break
  # the assumption that contact_id is always coherent with the other two.

  def broadcast_relevant_change?
    saved_change_to_due_date? || saved_change_to_title? || saved_change_to_assignee_id?
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
