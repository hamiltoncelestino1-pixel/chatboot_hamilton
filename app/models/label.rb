# == Schema Information
#
# Table name: labels
#
#  id              :bigint           not null, primary key
#  color           :string           default("#1f93ff"), not null
#  description     :text
#  label_type      :integer          default("general_label"), not null
#  show_on_sidebar :boolean
#  title           :string
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  account_id      :bigint
#
# Indexes
#
#  index_labels_on_account_id                 (account_id)
#  index_labels_on_label_type_and_account_id  (label_type,account_id)
#  index_labels_on_title_and_account_id       (title,account_id) UNIQUE
#
class Label < ApplicationRecord
  include RegexHelper
  include AccountCacheRevalidator

  belongs_to :account

  enum label_type: { general_label: 0, pipeline_label: 1 }

  scope :general, -> { where(label_type: :general_label) }
  scope :for_pipelines, -> { where(label_type: :pipeline_label) }

  validates :title,
            presence: { message: I18n.t('errors.validations.presence') },
            format: { with: UNICODE_CHARACTER_NUMBER_HYPHEN_UNDERSCORE },
            uniqueness: { scope: :account_id }

  after_update_commit :update_associated_models
  default_scope { order(:title) }

  before_validation do
    self.title = title.downcase if attribute_present?('title')
  end

  def conversations
    account.conversations.tagged_with(title)
  end

  def messages
    account.messages.where(conversation_id: conversations.pluck(:id))
  end

  def reporting_events
    account.reporting_events.where(conversation_id: conversations.pluck(:id))
  end

  private

  def update_associated_models
    return unless title_previously_changed?

    Labels::UpdateJob.perform_later(title, title_previously_was, account_id)
  end
end
