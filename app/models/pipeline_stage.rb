# == Schema Information
#
# Table name: pipeline_stages
#
#  id          :bigint           not null, primary key
#  color       :string(10)       default("#1f93ff"), not null
#  name        :string(255)      not null
#  position    :integer          default(0), not null
#  stage_type  :integer          default("normal"), not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  account_id  :bigint           not null
#  pipeline_id :bigint           not null
#
# Indexes
#
#  index_pipeline_stages_on_account_id                (account_id)
#  index_pipeline_stages_on_pipeline_id               (pipeline_id)
#  index_pipeline_stages_on_pipeline_id_and_name      (pipeline_id,name) UNIQUE
#  index_pipeline_stages_on_pipeline_id_and_position  (pipeline_id,position)
#
class PipelineStage < ApplicationRecord
  belongs_to :account
  belongs_to :pipeline
  has_many :pipeline_items, -> { order(:position) }, dependent: :destroy_async

  enum stage_type: { normal: 0, start: 1, won: 2, lost: 3 }

  validates :name,
            presence: { message: I18n.t('errors.validations.presence') },
            uniqueness: { scope: :pipeline_id }
  validates :stage_type, uniqueness: { scope: :pipeline_id }, unless: :normal?

  before_destroy :prevent_special_stage_deletion

  def push_event_data
    { id: id, name: name, color: color, position: position, pipeline_id: pipeline_id, stage_type: stage_type }
  end

  private

  def prevent_special_stage_deletion
    return if normal?

    errors.add(:base, I18n.t('errors.pipeline_stage.cannot_delete_special_stage'))
    throw :abort
  end
end
