import { DEFAULT_KANBAN_FILTERS, DEFAULT_KANBAN_SORT } from './constants';

function isWithinRange(value, range) {
  if (!value) return false;
  const t = value * 1000; // epoch seconds → ms
  if (range.from && t < new Date(range.from).getTime()) return false;
  if (range.to && t > new Date(range.to).getTime() + 86400000 - 1) return false;
  return true;
}

function compareByField(a, b, field) {
  if (field === 'value') return (Number(a.value) || 0) - (Number(b.value) || 0);
  if (field === 'assignee') {
    return (a.assignee?.name || '').localeCompare(b.assignee?.name || '');
  }
  return (a[field] || 0) - (b[field] || 0); // epoch seconds
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
    ($state.itemOrder[stageId] || [])
      .map(id => $state.items[id])
      .filter(Boolean),

  getUIFlags: $state => $state.uiFlags,

  getActiveFilters: $state => $state.activeFilters,
  getActiveSort: $state => $state.activeSort,
  getShowOnlyMine: $state => $state.showOnlyMine,

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

  getFilteredSortedItemsForStage:
    ($state, $getters) => (stageId, currentUserId) => {
      let items = $getters.getItemsForStage(stageId);
      const {
        assigneeId,
        createdAtRange,
        updatedAtRange,
        valueRange,
        labelTitles,
      } = $state.activeFilters;

      if ($state.showOnlyMine && currentUserId) {
        items = items.filter(i => i.assignee?.id === currentUserId);
      }
      if (assigneeId === 'unassigned') {
        items = items.filter(i => !i.assignee);
      } else if (assigneeId) {
        items = items.filter(i => i.assignee?.id === assigneeId);
      }
      if (createdAtRange)
        items = items.filter(i => isWithinRange(i.created_at, createdAtRange));
      if (updatedAtRange)
        items = items.filter(i => isWithinRange(i.updated_at, updatedAtRange));
      if (valueRange) {
        items = items.filter(i => {
          const v = Number(i.value) || 0;
          if (valueRange.min != null && v < valueRange.min) return false;
          if (valueRange.max != null && v > valueRange.max) return false;
          return true;
        });
      }
      if (labelTitles?.length) {
        items = items.filter(i =>
          (i.label_list || []).some(title => labelTitles.includes(title))
        );
      }

      const { field, order } = $state.activeSort;
      const dir = order === 'asc' ? 1 : -1;
      return [...items].sort((a, b) => compareByField(a, b, field) * dir);
    },

  getItemsForContact: $state => contactId =>
    Object.values($state.items).filter(i => i.contact?.id === contactId),

  getItemsForConversation: $state => conversationId =>
    Object.values($state.items).filter(
      i => i.conversation_id === conversationId
    ),
};
