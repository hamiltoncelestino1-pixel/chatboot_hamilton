# frozen_string_literal: true

FactoryBot.define do
  factory :pipeline_item do
    sequence(:title) { |n| "Oportunidade_#{n}" }
    value { 1000.0 }
    notes { 'Nota de teste' }

    after(:build) do |item|
      item.pipeline_stage ||= create(:pipeline_stage)
      item.account ||= item.pipeline_stage.account
      item.contact ||= create(:contact, account: item.account)
    end

    trait :with_assignee do
      after(:create) do |item|
        user = create(:user, account: item.account, role: :agent)
        create(:pipeline_member, pipeline: item.pipeline_stage.pipeline, user: user)
        item.update!(assignee: user)
      end
    end
  end
end
