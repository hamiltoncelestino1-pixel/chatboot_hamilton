# == Schema Information
#
# Table name: pipeline_lost_reasons
#
#  id         :bigint           not null, primary key
#  title      :string           not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  account_id :bigint           not null
#
# Indexes
#
#  index_pipeline_lost_reasons_on_account_id            (account_id)
#  index_pipeline_lost_reasons_on_account_id_and_title  (account_id,title) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#
class PipelineLostReason < ApplicationRecord
  belongs_to :account
  has_many :pipeline_items, dependent: :nullify

  validates :title, presence: true, uniqueness: { scope: :account_id }
end
