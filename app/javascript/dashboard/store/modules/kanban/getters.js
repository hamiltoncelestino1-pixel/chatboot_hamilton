import { DEFAULT_KANBAN_FILTERS, DEFAULT_KANBAN_SORT } from './constants';

function isWithinRange(value, range) {
  if (!value) return false;
  const t = value * 1000; // epoch seconds → ms
  if (range.from && t < new Date(range.from).getTime()) return false;
  if (range.to && t > new Date(range.to).getTime() + 86400000 - 1) return false;
  return true;
}

// Used by applyRealtimePipelineItem (actions.js) to decide whether an incoming realtime update
// still belongs in the active filtered view. Filtering/sorting for the board itself happens
// server-side (task 03) - this is the only place left that re-implements the predicate client-side.
export function itemMatchesActiveFilters($state, item, currentUserId) {
  const {
    assigneeId,
    createdAtRange,
    updatedAtRange,
    valueRange,
    labelTitles,
  } = $state.activeFilters;

  if (
    $state.showOnlyMine &&
    currentUserId &&
    item.assignee?.id !== currentUserId
  ) {
    return false;
  }
  if (assigneeId === 'unassigned' && item.assignee) return false;
  if (
    assigneeId &&
    assigneeId !== 'unassigned' &&
    item.assignee?.id !== assigneeId
  ) {
    return false;
  }
  if (createdAtRange && !isWithinRange(item.created_at, createdAtRange)) {
    return false;
  }
  if (updatedAtRange && !isWithinRange(item.updated_at, updatedAtRange)) {
    return false;
  }
  if (valueRange) {
    const v = Number(item.value) || 0;
    if (valueRange.min != null && v < valueRange.min) return false;
    if (valueRange.max != null && v > valueRange.max) return false;
  }
  if (
    labelTitles?.length &&
    !(item.label_list || []).some(title => labelTitles.includes(title))
  ) {
    return false;
  }
  return true;
}

const toEpochSeconds = dateStr =>
  Math.floor(new Date(dateStr).getTime() / 1000);

// Serializes activeFilters/activeSort/showOnlyMine into the query params the board's fetch
// actions (task 03/05) and the "run macro on this column" execute call (task 07) expect - the
// same semantics itemMatchesActiveFilters applies client-side, travelling as request params
// instead. Exported both for actions.js and for components (via the getActiveFilterParams getter
// below) that need to send exactly what the agent is currently looking at.
export function buildKanbanQueryParams($state) {
  const { activeFilters, activeSort, showOnlyMine } = $state;
  const params = {
    sort_by: activeSort.field,
    order: activeSort.order,
  };
  if (showOnlyMine) params.only_mine = true;
  if (activeFilters.assigneeId != null) {
    params.assignee_id = activeFilters.assigneeId;
  }
  if (activeFilters.createdAtRange?.from) {
    params.created_at_from = toEpochSeconds(activeFilters.createdAtRange.from);
  }
  if (activeFilters.createdAtRange?.to) {
    params.created_at_to = toEpochSeconds(activeFilters.createdAtRange.to);
  }
  if (activeFilters.updatedAtRange?.from) {
    params.updated_at_from = toEpochSeconds(activeFilters.updatedAtRange.from);
  }
  if (activeFilters.updatedAtRange?.to) {
    params.updated_at_to = toEpochSeconds(activeFilters.updatedAtRange.to);
  }
  if (activeFilters.valueRange?.min != null) {
    params.value_min = activeFilters.valueRange.min;
  }
  if (activeFilters.valueRange?.max != null) {
    params.value_max = activeFilters.valueRange.max;
  }
  if (activeFilters.labelTitles?.length) {
    params.label_titles = activeFilters.labelTitles;
  }
  return params;
}

export const getters = {
  getPipelines: $state =>
    $state.pipelineOrder.map(id => $state.pipelines[id]).filter(Boolean),

  getActivePipeline: $state =>
    $state.pipelines[$state.activePipelineId] || null,

  getStagesForPipeline: $state => pipelineId =>
    ($state.stageOrder[pipelineId] || [])
      .map(id => $state.stages[id])
      .filter(Boolean),

  getItemsForStage: $state => stageId =>
    ($state.stageItems[stageId]?.ids || [])
      .map(id => $state.items[id])
      .filter(Boolean),

  // Pagination/loading metadata for one column - count/hasMore come from the server, not from
  // how many ids happen to be loaded (task 05).
  getStageItemsMeta: $state => stageId =>
    $state.stageItems[stageId] || {
      ids: [],
      page: 1,
      count: 0,
      hasMore: true,
      isFetching: false,
      hasError: false,
    },

  getUIFlags: $state => $state.uiFlags,

  getActiveFilters: $state => $state.activeFilters,
  getActiveSort: $state => $state.activeSort,
  getShowOnlyMine: $state => $state.showOnlyMine,

  // What "the board's active filters" means as request params - used to run a macro on a whole
  // column server-side (task 07) with the same scope the agent is currently looking at.
  getActiveFilterParams: $state => buildKanbanQueryParams($state),

  isSortActive: $state =>
    $state.activeSort.field !== DEFAULT_KANBAN_SORT.field ||
    $state.activeSort.order !== DEFAULT_KANBAN_SORT.order,

  isFilterActive: $state =>
    Object.keys(DEFAULT_KANBAN_FILTERS).some(
      key => $state.activeFilters[key] !== DEFAULT_KANBAN_FILTERS[key]
    ),

  isBoardFiltered: $state =>
    $state.showOnlyMine ||
    Object.keys(DEFAULT_KANBAN_FILTERS).some(
      key => $state.activeFilters[key] !== DEFAULT_KANBAN_FILTERS[key]
    ) ||
    $state.activeSort.field !== DEFAULT_KANBAN_SORT.field ||
    $state.activeSort.order !== DEFAULT_KANBAN_SORT.order,

  // Maps ids from the lookup indices instead of scanning every item ever loaded (task 10).
  getItemsForContact: $state => contactId =>
    ($state.itemIdsByContact[contactId] || [])
      .map(id => $state.items[id])
      .filter(Boolean),

  getItemsForConversation: $state => conversationId =>
    ($state.itemIdsByConversation[conversationId] || [])
      .map(id => $state.items[id])
      .filter(Boolean),
};
