# frozen_string_literal: true

FactoryBot.define do
  factory :pipeline_member do
    after(:build) do |member|
      member.pipeline ||= create(:pipeline)
      member.user ||= create(:user, account: member.pipeline.account, role: :agent)
    end
  end
end
