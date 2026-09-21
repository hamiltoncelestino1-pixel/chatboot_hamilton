# Filters, sorts and paginates pipeline items for one board column (one stage). Mirrors the
# client-side semantics in app/javascript/dashboard/store/modules/kanban/getters.js
# (getFilteredSortedItemsForStage) - keep the two in sync, they must agree until the frontend
# switches to this endpoint (claude/pipeline_performance_tasks/06-ui-scroll-infinito-por-coluna.md).
class PipelineItemFinder
  attr_reader :scope, :stage_id, :current_user, :params

  RESULTS_PER_PAGE = ENV.fetch('PIPELINE_ITEMS_RESULTS_PER_PAGE', '25').to_i

  # Column each sort_by resolves to. Whitelisted on purpose - params[:sort_by] must never reach
  # SQL directly.
  SORT_COLUMNS = {
    'position' => 'pipeline_items.position',
    'created_at' => 'pipeline_items.created_at',
    'updated_at' => 'pipeline_items.updated_at',
    'value' => 'pipeline_items.value'
  }.freeze

  def initialize(scope:, stage_id:, current_user:, params:)
    @scope = scope
    @stage_id = stage_id
    @current_user = current_user
    @params = params
  end

  def perform
    apply_sort(filtered_scope).page(current_page).per(RESULTS_PER_PAGE)
  end

  # Every item matching the stage + active filters, unpaginated and unordered - what "the
  # column" means under the current filters, for callers that need the whole set rather than one
  # page of it (e.g. running a macro on every card in a column - task 07).
  def filtered_scope
    apply_filters(scope.where(pipeline_stage_id: stage_id))
  end

  def current_page
    params[:page] || 1
  end

  private

  def apply_filters(items)
    items = filter_by_assignee(items)
    items = filter_by_date_range(items, :created_at, params[:created_at_from], params[:created_at_to])
    items = filter_by_date_range(items, :updated_at, params[:updated_at_from], params[:updated_at_to])
    items = filter_by_value_range(items)
    filter_by_labels(items)
  end

  # AND, not "showOnlyMine wins": both conditions apply when both are present, same as the
  # client's itemMatchesActiveFilters (getters.js) - "somente meus" + assignee_id of someone else
  # is a real, if useless, combination that means "no cards", not "ignore the assignee filter"
  # (task 17 - the two used to disagree here, one exclusive and one cumulative).
  def filter_by_assignee(items)
    items = items.where(pipeline_items: { assignee_id: current_user.id }) if ActiveModel::Type::Boolean.new.cast(params[:only_mine])
    return items if params[:assignee_id].blank?
    return items.where(pipeline_items: { assignee_id: nil }) if params[:assignee_id] == 'unassigned'

    items.where(pipeline_items: { assignee_id: params[:assignee_id] })
  end

  # `to` is a calendar day boundary from the client (a date picker, not a timestamp) - it has to
  # include the whole day, mirroring isWithinRange's `+ 86400000 - 1` in getters.js.
  def filter_by_date_range(items, column, from_param, to_param)
    return items if from_param.blank? && to_param.blank?

    from = from_param.present? ? Time.zone.at(from_param.to_i) : nil
    to = to_param.present? ? Time.zone.at(to_param.to_i) + 1.day - 1.second : nil
    items.where(pipeline_items: { column => from..to })
  end

  # NULL treated as 0, same as the client's `Number(item.value) || 0` (getters.js) - a plain
  # `value: min..max` range excludes NULL rows outright (`NULL BETWEEN x AND y` is NULL, not
  # true, in SQL), which would hide exactly the cards an agent filtering "0 to 1000" for
  # small/unpriced opportunities is looking for (task 20).
  def filter_by_value_range(items)
    return items if params[:value_min].blank? && params[:value_max].blank?

    min = params[:value_min].presence&.to_f
    max = params[:value_max].presence&.to_f
    items = items.where('COALESCE(pipeline_items.value, 0) >= ?', min) if min
    items = items.where('COALESCE(pipeline_items.value, 0) <= ?', max) if max
    items
  end

  # OR semantics, not AND - matches the client's `.some()` (getters.js:90-93), not
  # ConversationFinder#filter_by_labels' AND-by-default tagged_with usage elsewhere.
  def filter_by_labels(items)
    return items if params[:label_titles].blank?

    items.tagged_with(Array(params[:label_titles]), any: true)
  end

  # #reorder, not #order: both PipelineStage#pipeline_items and Pipeline#pipeline_stages carry
  # their own `order(:position)` scope, which .order would only append after (losing) - .reorder
  # replaces it so this sort is actually authoritative.
  #
  # `pipeline_items.id` is appended as a tiebreaker on every branch: ties on the primary column
  # are the rule here, not the exception (position defaults to 0 and nothing assigns it on
  # create), and LIMIT/OFFSET over a non-deterministic order has no guarantee of partitioning the
  # set - the same row can come back on two pages, and another row on none.
  def apply_sort(items)
    order = params[:order] == 'desc' ? 'desc' : 'asc'

    if params[:sort_by] == 'assignee'
      # Null assignee sorts like an empty name, same as the client's `a.assignee?.name || ''`
      # (getters.js:13-15).
      items.left_joins(:assignee).reorder(Arel.sql("COALESCE(users.name, '') #{order}, pipeline_items.id #{order}"))
    else
      column = SORT_COLUMNS[params[:sort_by]] || SORT_COLUMNS['position']
      items.reorder(Arel.sql("#{column} #{order}, pipeline_items.id #{order}"))
    end
  end
end
PipelineItemFinder.prepend_mod_with('PipelineItemFinder')
