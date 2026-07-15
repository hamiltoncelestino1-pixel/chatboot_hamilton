# frozen_string_literal: true

FactoryBot.define do
  factory :pipeline do
    sequence(:name) { |n| "Pipeline_#{n}" }
    description { 'Pipeline de teste' }

    after(:build) do |pipeline|
      pipeline.account ||= create(:account)
    end
  end
end
