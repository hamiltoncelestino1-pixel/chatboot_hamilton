import { actions } from '../actions';

describe('kanban/actions', () => {
  describe('applyRealtimePipelineItem', () => {
    it('ignores items outside the currently active pipeline', () => {
      const commit = vi.fn();
      const state = { activePipelineId: 1, items: {} };

      actions.applyRealtimePipelineItem(
        { commit, state },
        { id: 5, pipeline_id: 2, pipeline_stage_id: 3 }
      );

      expect(commit).not.toHaveBeenCalled();
    });

    it('adds a new item straight to its stage', () => {
      const commit = vi.fn();
      const state = { activePipelineId: 1, items: {} };
      const item = { id: 5, pipeline_id: 1, pipeline_stage_id: 3 };

      actions.applyRealtimePipelineItem({ commit, state }, item);

      expect(commit).toHaveBeenCalledTimes(1);
      expect(commit).toHaveBeenCalledWith('SET_ITEM', item);
    });

    it('moves an existing item whose stage changed, then applies the full update', () => {
      const commit = vi.fn();
      const state = {
        activePipelineId: 1,
        items: { 5: { id: 5, pipeline_id: 1, pipeline_stage_id: 3 } },
      };
      const item = { id: 5, pipeline_id: 1, pipeline_stage_id: 7 };

      actions.applyRealtimePipelineItem({ commit, state }, item);

      expect(commit).toHaveBeenNthCalledWith(1, 'MOVE_ITEM', {
        itemId: 5,
        fromStageId: 3,
        toStageId: 7,
        position: 0,
      });
      expect(commit).toHaveBeenNthCalledWith(2, 'SET_ITEM', item);
    });

    it('does not call MOVE_ITEM when the stage is unchanged', () => {
      const commit = vi.fn();
      const state = {
        activePipelineId: 1,
        items: { 5: { id: 5, pipeline_id: 1, pipeline_stage_id: 3 } },
      };
      const item = {
        id: 5,
        pipeline_id: 1,
        pipeline_stage_id: 3,
        title: 'Updated',
      };

      actions.applyRealtimePipelineItem({ commit, state }, item);

      expect(commit).toHaveBeenCalledTimes(1);
      expect(commit).toHaveBeenCalledWith('SET_ITEM', item);
    });
  });
});
