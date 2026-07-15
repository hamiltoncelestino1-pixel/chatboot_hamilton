import { getters } from '../getters';
import { DEFAULT_KANBAN_FILTERS, DEFAULT_KANBAN_SORT } from '../constants';

const makeState = (overrides = {}) => ({
  activeFilters: { ...DEFAULT_KANBAN_FILTERS },
  activeSort: { ...DEFAULT_KANBAN_SORT },
  showOnlyMine: false,
  itemOrder: {},
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

const makeGetters = items => ({
  getItemsForStage: stageId =>
    items.filter(i => i.pipeline_stage_id === stageId),
});

describe('kanban/getters', () => {
  describe('getFilteredSortedItemsForStage', () => {
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

    const $getters = makeGetters(allItems);

    it('returns all items when no filters active', () => {
      const $state = makeState();
      const result = getters.getFilteredSortedItemsForStage($state, $getters)(
        1,
        agent1.id
      );
      expect(result).toHaveLength(3);
    });

    it('filters by showOnlyMine', () => {
      const $state = makeState({ showOnlyMine: true });
      const result = getters.getFilteredSortedItemsForStage($state, $getters)(
        1,
        agent1.id
      );
      expect(result).toHaveLength(1);
      expect(result[0].id).toBe(1);
    });

    it('filters assigneeId = "unassigned"', () => {
      const $state = makeState({
        activeFilters: { ...DEFAULT_KANBAN_FILTERS, assigneeId: 'unassigned' },
      });
      const result = getters.getFilteredSortedItemsForStage($state, $getters)(
        1,
        null
      );
      expect(result).toHaveLength(1);
      expect(result[0].id).toBe(3);
    });

    it('filters assigneeId by specific id', () => {
      const $state = makeState({
        activeFilters: { ...DEFAULT_KANBAN_FILTERS, assigneeId: agent2.id },
      });
      const result = getters.getFilteredSortedItemsForStage($state, $getters)(
        1,
        null
      );
      expect(result).toHaveLength(1);
      expect(result[0].id).toBe(2);
    });

    it('filters by createdAtRange', () => {
      const $state = makeState({
        activeFilters: {
          ...DEFAULT_KANBAN_FILTERS,
          createdAtRange: { from: '2024-01-08', to: '2024-01-12' },
        },
      });
      const result = getters.getFilteredSortedItemsForStage($state, $getters)(
        1,
        null
      );
      expect(result).toHaveLength(1);
      expect(result[0].id).toBe(3);
    });

    it('filters by updatedAtRange', () => {
      const $state = makeState({
        activeFilters: {
          ...DEFAULT_KANBAN_FILTERS,
          updatedAtRange: { from: '2024-01-18', to: '2024-01-22' },
        },
      });
      const result = getters.getFilteredSortedItemsForStage($state, $getters)(
        1,
        null
      );
      expect(result).toHaveLength(1);
      expect(result[0].id).toBe(2);
    });

    it('filters by valueRange min and max', () => {
      const $state = makeState({
        activeFilters: {
          ...DEFAULT_KANBAN_FILTERS,
          valueRange: { min: 600, max: 1500 },
        },
      });
      const result = getters.getFilteredSortedItemsForStage($state, $getters)(
        1,
        null
      );
      expect(result).toHaveLength(1);
      expect(result[0].id).toBe(3);
    });

    it('sorts by value asc', () => {
      const $state = makeState({
        activeSort: { field: 'value', order: 'asc' },
      });
      const result = getters.getFilteredSortedItemsForStage($state, $getters)(
        1,
        null
      );
      expect(result.map(i => i.id)).toEqual([1, 3, 2]);
    });

    it('sorts by value desc', () => {
      const $state = makeState({
        activeSort: { field: 'value', order: 'desc' },
      });
      const result = getters.getFilteredSortedItemsForStage($state, $getters)(
        1,
        null
      );
      expect(result.map(i => i.id)).toEqual([2, 3, 1]);
    });

    it('sorts by assignee name asc', () => {
      const $state = makeState({
        activeSort: { field: 'assignee', order: 'asc' },
      });
      const result = getters.getFilteredSortedItemsForStage($state, $getters)(
        1,
        null
      );
      // null assignee sorts as '' which comes before Alice and Bob
      expect(result[0].id).toBe(3);
      expect(result[1].id).toBe(1); // Alice
      expect(result[2].id).toBe(2); // Bob
    });

    it('sorts by created_at desc', () => {
      const $state = makeState({
        activeSort: { field: 'created_at', order: 'desc' },
      });
      const result = getters.getFilteredSortedItemsForStage($state, $getters)(
        1,
        null
      );
      expect(result.map(i => i.id)).toEqual([2, 3, 1]);
    });

    it('combines createdAtRange filter with valueRange', () => {
      const $state = makeState({
        activeFilters: {
          ...DEFAULT_KANBAN_FILTERS,
          createdAtRange: { from: '2024-01-01', to: '2024-01-12' },
          valueRange: { min: 600, max: null },
        },
      });
      const result = getters.getFilteredSortedItemsForStage($state, $getters)(
        1,
        null
      );
      // items 1 (500, filtered by valueRange) and 3 (1000, passes both) pass createdAtRange; item 2 is out of date range
      expect(result).toHaveLength(1);
      expect(result[0].id).toBe(3);
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
