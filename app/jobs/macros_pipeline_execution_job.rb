class MacrosPipelineExecutionJob < ApplicationJob
  queue_as :default

  def perform(macro, pipeline_item_ids:, user:)
    account = macro.account
    items = account.pipeline_items.where(id: pipeline_item_ids)

    return if items.blank?

    items.each do |item|
      ::Macros::PipelineExecutionService.new(macro, item, user).perform
    end
  end
end
