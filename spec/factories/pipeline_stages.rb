# frozen_string_literal: true

FactoryBot.define do
  factory :pipeline_stage do
    sequence(:name) { |n| "Stage_#{n}" }
    color { '#1f93ff' }
    stage_type { :normal }

    after(:build) do |stage|
      stage.pipeline ||= create(:pipeline)
      stage.account ||= stage.pipeline.account
    end

    trait :start do
      stage_type { :start }
    end

    trait :won do
      stage_type { :won }
    end

    trait :lost do
      stage_type { :lost }
    end
  end
end
