export const DEFAULT_KANBAN_FILTERS = Object.freeze({
  assigneeId: null,
  createdAtRange: null,
  updatedAtRange: null,
  valueRange: null,
  labelTitles: null,
});

export const DEFAULT_KANBAN_SORT = Object.freeze({
  field: 'created_at',
  order: 'desc',
});
