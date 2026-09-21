import { getters, itemMatchesActiveFilters } from '../getters';
import { DEFAULT_KANBAN_FILTERS, DEFAULT_KANBAN_SORT } from '../constants';

const makeState = (overrides = {}) => ({
  activeFilters: { ...DEFAULT_KANBAN_FILTERS },
  activeSort: { ...DEFAULT_KANBAN_SORT },
  showOnlyMine: false,
  stageItems: {},
  items: {},
  ...overrides,
});

const item = (id, overrides = {}) => ({
  id,
  title: `Item ${id}`,
  value: '1000.00',
  assignee: null,
  created_at: 1704844800, // 2024-01-10 UTC
  updated_at: 1704844800, // 2024-01-10 UTC
  pipeline_stage_id: 1,
  ...overrides,
});

describe('kanban/getters', () => {
  // Filtering/sorting for the board itself is server-side (task 03/08) - itemMatchesActiveFilters
  // is what's left client-side, used by applyRealtimePipelineItem to decide whether an incoming
  // realtime update still belongs in the active filtered view.
  describe('itemMatchesActiveFilters', () => {
    const agent1 = { id: 10, name: 'Alice' };
    const agent2 = { id: 20, name: 'Bob' };

    const allItems = [
      item(1, {
        assignee: agent1,
        value: '500',
        created_at: 1704412800,
        updated_at: 1704412800,
      }), // 2024-01-05
      item(2, {
        assignee: agent2,
        value: '2000',
        created_at: 1705276800,
        updated_at: 1705708800,
      }), // 2024-01-15 / 2024-01-20
      item(3, {
        assignee: null,
        value: '1000',
        created_at: 1704844800,
        updated_at: 1704844800,
      }), // 2024-01-10
    ];

    const matching = ($state, currentUserId) =>
      allItems
        .filter(i => itemMatchesActiveFilters($state, i, currentUserId))
        .map(i => i.id);

    it('returns all items when no filters active', () => {
      const $state = makeState();
      expect(matching($state, agent1.id)).toEqual([1, 2, 3]);
    });

    it('filters by showOnlyMine', () => {
      const $state = makeState({ showOnlyMine: true });
      expect(matching($state, agent1.id)).toEqual([1]);
    });

    it('filters assigneeId = "unassigned"', () => {
      const $state = makeState({
        activeFilters: { ...DEFAULT_KANBAN_FILTERS, assigneeId: 'unassigned' },
      });
      expect(matching($state, null)).toEqual([3]);
    });

    it('filters assigneeId by specific id', () => {
      const $state = makeState({
        activeFilters: { ...DEFAULT_KANBAN_FILTERS, assigneeId: agent2.id },
      });
      expect(matching($state, null)).toEqual([2]);
    });

    it('filters by createdAtRange', () => {
      const $state = makeState({
        activeFilters: {
          ...DEFAULT_KANBAN_FILTERS,
          createdAtRange: { from: '2024-01-08', to: '2024-01-12' },
        },
      });
      expect(matching($state, null)).toEqual([3]);
    });

    it('filters by updatedAtRange', () => {
      const $state = makeState({
        activeFilters: {
          ...DEFAULT_KANBAN_FILTERS,
          updatedAtRange: { from: '2024-01-18', to: '2024-01-22' },
        },
      });
      expect(matching($state, null)).toEqual([2]);
    });

    it('filters by valueRange min and max', () => {
      const $state = makeState({
        activeFilters: {
          ...DEFAULT_KANBAN_FILTERS,
          valueRange: { min: 600, max: 1500 },
        },
      });
      expect(matching($state, null)).toEqual([3]);
    });

    it('combines createdAtRange filter with valueRange', () => {
      const $state = makeState({
        activeFilters: {
          ...DEFAULT_KANBAN_FILTERS,
          createdAtRange: { from: '2024-01-01', to: '2024-01-12' },
          valueRange: { min: 600, max: null },
        },
      });
      // items 1 (500, filtered by valueRange) and 3 (1000, passes both) pass createdAtRange; item 2 is out of date range
      expect(matching($state, null)).toEqual([3]);
    });
  });

  describe('isSortActive', () => {
    it('is false when sort is default', () => {
      const $state = makeState();
      expect(getters.isSortActive($state)).toBe(false);
    });

    it('is true when sort field differs from default', () => {
      const $state = makeState({
        activeSort: { field: 'value', order: 'desc' },
      });
      expect(getters.isSortActive($state)).toBe(true);
    });

    it('is true when sort order differs from default', () => {
      const $state = makeState({
        activeSort: { field: 'created_at', order: 'asc' },
      });
      expect(getters.isSortActive($state)).toBe(true);
    });

    it('is false when only filters are active (sort remains default)', () => {
      const $state = makeState({
        activeFilters: { ...DEFAULT_KANBAN_FILTERS, assigneeId: 5 },
      });
      expect(getters.isSortActive($state)).toBe(false);
    });
  });

  describe('isBoardFiltered', () => {
    it('is false when nothing is active', () => {
      const $state = makeState();
      expect(getters.isBoardFiltered($state)).toBe(false);
    });

    it('is true when showOnlyMine is true', () => {
      const $state = makeState({ showOnlyMine: true });
      expect(getters.isBoardFiltered($state)).toBe(true);
    });

    it('is true when a filter is set', () => {
      const $state = makeState({
        activeFilters: { ...DEFAULT_KANBAN_FILTERS, assigneeId: 5 },
      });
      expect(getters.isBoardFiltered($state)).toBe(true);
    });

    it('is true when sort field differs from default', () => {
      const $state = makeState({
        activeSort: { field: 'value', order: 'desc' },
      });
      expect(getters.isBoardFiltered($state)).toBe(true);
    });

    it('is true when sort order differs from default', () => {
      const $state = makeState({
        activeSort: { field: 'created_at', order: 'asc' },
      });
      expect(getters.isBoardFiltered($state)).toBe(true);
    });
  });
});
