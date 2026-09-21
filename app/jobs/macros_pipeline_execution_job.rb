class MacrosPipelineExecutionJob < ApplicationJob
  queue_as :default

  # Either pipeline_item_ids (single card, or an explicit list) or stage_id (+ filters, run on
  # every card currently in that column - task 07). The stage_id case is resolved here, against
  # live data at execution time, rather than a list of ids captured back when the agent clicked -
  # by design, since the whole point is to not be limited to whatever page was loaded client-side.
  def perform(macro, user:, pipeline_item_ids: nil, stage_id: nil, filters: {})
    account = macro.account
    items = stage_id.present? ? items_for_stage(account, stage_id, filters, user) : account.pipeline_items.where(id: pipeline_item_ids)

    # find_each, not each: a column-wide macro (task 07) resolves against the whole (unpaginated,
    # unordered - see PipelineItemFinder#filtered_scope) filtered stage, which can be a lot more
    # than the page a client had loaded. .each/.blank? would materialize every matching row as an
    # AR object at once; find_each fetches in batches (id order, which is fine - execution order
    # doesn't matter here) and simply does nothing on an empty relation, so there's no separate
    # blank? guard to keep in sync with it (task 19).
    items.find_each(batch_size: 100) do |item|
      ::Macros::PipelineExecutionService.new(macro, item, user).perform
    end
  end

  private

  def items_for_stage(account, stage_id, filters, user)
    stage = account.pipeline_stages.find_by(id: stage_id)
    return PipelineItem.none if stage.blank?

    PipelineItemFinder.new(
      scope: account.pipeline_items, stage_id: stage.id, current_user: user, params: (filters || {}).with_indifferent_access
    ).filtered_scope
  end
end
