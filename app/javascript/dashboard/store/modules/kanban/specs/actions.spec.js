import { actions } from '../actions';
import { DEFAULT_KANBAN_FILTERS, DEFAULT_KANBAN_SORT } from '../constants';

const rootGetters = { getCurrentUserID: 99 };

const makeState = (overrides = {}) => ({
  activePipelineId: 1,
  activeFilters: { ...DEFAULT_KANBAN_FILTERS },
  activeSort: { ...DEFAULT_KANBAN_SORT },
  showOnlyMine: false,
  items: {},
  stageItems: {},
  ...overrides,
});

describe('kanban/actions', () => {
  describe('applyRealtimePipelineItem', () => {
    it('ignores items outside the currently active pipeline', () => {
      const commit = vi.fn();
      const state = makeState();

      actions.applyRealtimePipelineItem(
        { commit, state, rootGetters },
        { id: 5, pipeline_id: 2, pipeline_stage_id: 3 }
      );

      expect(commit).not.toHaveBeenCalled();
    });

    it('marks the destination stage count for a new item that matches the active filters, without inserting it into any list', () => {
      const commit = vi.fn();
      const state = makeState();
      const item = { id: 5, pipeline_id: 1, pipeline_stage_id: 3 };

      actions.applyRealtimePipelineItem({ commit, state, rootGetters }, item);

      expect(commit).toHaveBeenCalledTimes(1);
      expect(commit).toHaveBeenCalledWith('SET_UNLOADED_ITEM_COUNTED', {
        stageId: 3,
        itemId: 5,
        counted: true,
      });
    });

    it('un-marks the destination stage count for a new item that does not match the active filters', () => {
      const commit = vi.fn();
      const state = makeState({
        activeFilters: { ...DEFAULT_KANBAN_FILTERS, assigneeId: 'unassigned' },
      });
      const item = {
        id: 5,
        pipeline_id: 1,
        pipeline_stage_id: 3,
        assignee: { id: 42, name: 'Alice' },
      };

      actions.applyRealtimePipelineItem({ commit, state, rootGetters }, item);

      expect(commit).toHaveBeenCalledTimes(1);
      expect(commit).toHaveBeenCalledWith('SET_UNLOADED_ITEM_COUNTED', {
        stageId: 3,
        itemId: 5,
        counted: false,
        previousStageId: null,
      });
    });

    it('moves an already-loaded item whose stage changed, then applies the field update', () => {
      const commit = vi.fn();
      const state = makeState({
        items: { 5: { id: 5, pipeline_id: 1, pipeline_stage_id: 3 } },
      });
      const item = { id: 5, pipeline_id: 1, pipeline_stage_id: 7 };

      actions.applyRealtimePipelineItem({ commit, state, rootGetters }, item);

      expect(commit).toHaveBeenNthCalledWith(1, 'MOVE_ITEM', {
        itemId: 5,
        fromStageId: 3,
        toStageId: 7,
        position: 0,
      });
      expect(commit).toHaveBeenNthCalledWith(2, 'EDIT_ITEM', item);
    });

    it('does not call MOVE_ITEM when the stage is unchanged, but still applies the field update', () => {
      const commit = vi.fn();
      const state = makeState({
        items: { 5: { id: 5, pipeline_id: 1, pipeline_stage_id: 3 } },
      });
      const item = {
        id: 5,
        pipeline_id: 1,
        pipeline_stage_id: 3,
        title: 'Updated',
      };

      actions.applyRealtimePipelineItem({ commit, state, rootGetters }, item);

      expect(commit).toHaveBeenCalledTimes(1);
      expect(commit).toHaveBeenCalledWith('EDIT_ITEM', item);
    });

    it('drops an already-loaded item from its stage when it no longer matches the active filters', () => {
      const commit = vi.fn();
      const state = makeState({
        activeFilters: { ...DEFAULT_KANBAN_FILTERS, assigneeId: 42 },
        items: {
          5: {
            id: 5,
            pipeline_id: 1,
            pipeline_stage_id: 3,
            assignee: { id: 42, name: 'Alice' },
          },
        },
      });
      // Reassigned away from the agent being filtered on - no longer matches.
      const item = {
        id: 5,
        pipeline_id: 1,
        pipeline_stage_id: 3,
        assignee: { id: 7, name: 'Bob' },
      };

      actions.applyRealtimePipelineItem({ commit, state, rootGetters }, item);

      expect(commit).toHaveBeenNthCalledWith(1, 'REMOVE_STAGE_ITEM', {
        stageId: 3,
        itemId: 5,
      });
      expect(commit).toHaveBeenNthCalledWith(2, 'EDIT_ITEM', item);
    });
  });
});
