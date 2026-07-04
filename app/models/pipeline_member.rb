# == Schema Information
#
# Table name: pipeline_members
#
#  id          :bigint           not null, primary key
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  pipeline_id :bigint           not null
#  user_id     :bigint           not null
#
# Indexes
#
#  index_pipeline_members_on_pipeline_id_and_user_id  (pipeline_id,user_id) UNIQUE
#  index_pipeline_members_on_user_id                  (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (pipeline_id => pipelines.id)
#  fk_rails_...  (user_id => users.id)
#
class PipelineMember < ApplicationRecord
  belongs_to :user
  belongs_to :pipeline

  validates :user_id, uniqueness: { scope: :pipeline_id }
end
