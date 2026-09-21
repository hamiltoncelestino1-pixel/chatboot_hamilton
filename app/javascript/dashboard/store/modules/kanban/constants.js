export const DEFAULT_KANBAN_FILTERS = Object.freeze({
  assigneeId: null,
  createdAtRange: null,
  updatedAtRange: null,
  valueRange: null,
  labelTitles: null,
});

// Matches the API default (task 03) - manual drag order, not recency.
export const DEFAULT_KANBAN_SORT = Object.freeze({
  field: 'position',
  order: 'asc',
});
