# == Schema Information
#
# Table name: pipeline_items
#
#  id                :bigint           not null, primary key
#  custom_attributes :jsonb            not null
#  notes             :text
#  position          :integer          default(0), not null
#  title             :string(255)
#  value             :decimal(15, 2)   default(0.0)
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  account_id        :bigint           not null
#  assignee_id       :bigint
#  contact_id        :bigint           not null
#  conversation_id   :bigint
#  pipeline_stage_id :bigint           not null
#  team_id           :bigint
#
# Indexes
#
#  index_pipeline_items_on_account_id                      (account_id)
#  index_pipeline_items_on_account_id_and_contact_id       (account_id,contact_id)
#  index_pipeline_items_on_assignee_id                     (assignee_id)
#  index_pipeline_items_on_contact_id                      (contact_id)
#  index_pipeline_items_on_conversation_id                 (conversation_id)
#  index_pipeline_items_on_pipeline_stage_id               (pipeline_stage_id)
#  index_pipeline_items_on_pipeline_stage_id_and_position  (pipeline_stage_id,position)
#  index_pipeline_items_on_team_id                         (team_id)
#
# Foreign Keys
#
#  fk_rails_...  (assignee_id => users.id)
#  fk_rails_...  (team_id => teams.id)
#
class PipelineItem < ApplicationRecord
  include Labelable

  belongs_to :account
  belongs_to :pipeline_stage
  belongs_to :contact
  belongs_to :conversation, optional: true
  belongs_to :assignee, class_name: 'User', optional: true
  belongs_to :team, optional: true

  validates :contact_id, presence: true
  validates :pipeline_stage_id, presence: true
  validate :assignee_must_be_pipeline_member
  validate :labels_must_be_pipeline_type
  validate :conversation_must_belong_to_contact, if: -> { conversation_id.present? }

  delegate :pipeline, to: :pipeline_stage

  private

  def labels_must_be_pipeline_type
    return if label_list.blank?

    allowed = account.labels.pipeline_label.pluck(:title)
    invalid = label_list - allowed
    errors.add(:label_list, "invalid pipeline labels: #{invalid.join(', ')}") if invalid.any?
  end

  def conversation_must_belong_to_contact
    return if conversation&.contact_id == contact_id

    errors.add(:conversation_id, I18n.t('errors.pipeline_item.conversation_contact_mismatch'))
  end

  def assignee_must_be_pipeline_member
    return if assignee_id.blank?
    return if assignee.administrator?
    return if pipeline.members.exists?(id: assignee_id)

    errors.add(:assignee_id, I18n.t('errors.pipeline_item.assignee_not_member'))
  end
end
