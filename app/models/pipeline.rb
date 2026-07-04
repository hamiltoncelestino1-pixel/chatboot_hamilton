# == Schema Information
#
# Table name: pipelines
#
#  id                     :bigint           not null, primary key
#  description            :text
#  enable_auto_assignment :boolean          default(FALSE), not null
#  max_assignment_limit   :integer          default(0), not null
#  name                   :string(255)      not null
#  position               :integer          default(0), not null
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#  account_id             :bigint           not null
#
# Indexes
#
#  index_pipelines_on_account_id               (account_id)
#  index_pipelines_on_account_id_and_name      (account_id,name) UNIQUE
#  index_pipelines_on_account_id_and_position  (account_id,position)
#
class Pipeline < ApplicationRecord
  belongs_to :account
  has_many :pipeline_stages, -> { order(:position) }, dependent: :destroy_async
  has_many :pipeline_items, through: :pipeline_stages
  has_many :pipeline_members, dependent: :destroy_async
  has_many :members, through: :pipeline_members, source: :user

  validates :name,
            presence: { message: I18n.t('errors.validations.presence') },
            uniqueness: { scope: :account_id }
  validates :max_assignment_limit, numericality: { greater_than_or_equal_to: 0 }

  default_scope { order(:position) }

  after_create :create_default_stages

  def add_members(user_ids)
    members_to_create = user_ids.map { |user_id| { user_id: user_id } }
    created_members = pipeline_members.create(members_to_create)
    created_members.filter_map(&:user)
  end

  def remove_members(user_ids)
    pipeline_members.where(user_id: user_ids).destroy_all
  end

  def push_event_data
    { id: id, name: name, position: position }
  end

  private

  def create_default_stages
    pipeline_stages.create!(name: 'Nova oportunidade', color: '#1f93ff', position: 0, stage_type: :start, account_id: account_id)
    pipeline_stages.create!(name: 'Ganho', color: '#1f9e51', position: 1, stage_type: :won, account_id: account_id)
    pipeline_stages.create!(name: 'Perdido', color: '#e35b5b', position: 2, stage_type: :lost, account_id: account_id)
  end
end
