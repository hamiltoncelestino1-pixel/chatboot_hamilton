import PipelinesAPI from 'dashboard/api/pipelines';
import PipelineItemsAPI from 'dashboard/api/pipelineItems';
import PipelineItemLabelsAPI from 'dashboard/api/pipelineItemLabels';
import { useAlert } from 'dashboard/composables';
import i18n from 'dashboard/i18n/instance';
import { useLostReasonPrompt } from 'dashboard/composables/useLostReasonPrompt';
import { throwErrorMessage } from '../../utils/api';
import { itemMatchesActiveFilters, buildKanbanQueryParams } from './getters';

// Where a card that a realtime push just moved into a stage belongs in that stage's loaded list
// (task 28), or null when it can't be placed there. The list is a prefix of the server's order,
// and that order is only `(position, id)` when the manual sort is active - for any other sort
// (value, created_at, ...) working out the slot would mean re-implementing the server's
// comparator, so the card is left out of the list and counted as unloaded instead: it shows up in
// the right place on the next fetch. Same when it sorts after everything loaded and the column
// has more pages - the cards in between aren't here, so appending it would put it too early.
// Positions come from `state.items`, which isn't refreshed for cards someone else reordered, so
// the slot can be off by a few places after manual reorders; the next fetch corrects it.
function realtimeInsertIndex(state, item) {
  if (state.activeSort.field !== 'position') return null;

  const stage = state.stageItems[item.pipeline_stage_id];
  const ids = stage?.ids || [];
  const index = ids.findIndex(id => {
    const other = state.items[id];
    if (!other) return false;
    return (
      other.position > item.position ||
      (other.position === item.position && other.id > item.id)
    );
  });
  if (index !== -1) return index;
  return stage?.hasMore ? null : ids.length;
}

export const actions = {
  fetchPipelines: async ({ commit }) => {
    commit('SET_KANBAN_UI_FLAG', { isFetchingPipelines: true });
    try {
      const { data } = await PipelinesAPI.get();
      commit('SET_PIPELINES', data);
    } finally {
      commit('SET_KANBAN_UI_FLAG', { isFetchingPipelines: false });
    }
  },

  // Page 1 of one column. Replaces whatever was loaded for that stage. Errors are caught here,
  // not left to the caller (task 21): resetBoard fans this out to every column via Promise.all,
  // and one column's rejection must not take the others down with it or surface as an unhandled
  // rejection - it turns into a per-column error state instead (KanbanColumn.vue), which is also
  // how the column tells "failed to load" apart from "genuinely empty".
  fetchStageItems: async ({ commit, state }, { pipelineId, stageId }) => {
    commit('SET_STAGE_FETCHING', { stageId, isFetching: true });
    try {
      const { data } = await PipelinesAPI.getBoardItems(pipelineId, {
        stage_id: stageId,
        page: 1,
        ...buildKanbanQueryParams(state),
      });
      commit('SET_STAGE_ITEMS_PAGE', {
        stageId,
        items: data.payload,
        count: data.meta.count,
        page: 1,
      });
    } catch {
      commit('SET_STAGE_ERROR', { stageId, hasError: true });
    } finally {
      commit('SET_STAGE_FETCHING', { stageId, isFetching: false });
    }
  },

  // Next page of one column, appended. No-op if already fetching or there's nothing more to
  // load - the IntersectionObserver driving this (task 06) can fire more than once in a row.
  // Same error handling as fetchStageItems (task 21) - a failed "load more" leaves the already-
  // loaded cards on screen and marks the column so the observer stops retrying in a loop.
  fetchMoreStageItems: async ({ commit, state }, { pipelineId, stageId }) => {
    const current = state.stageItems[stageId];
    if (!current || current.isFetching || !current.hasMore) return;

    commit('SET_STAGE_FETCHING', { stageId, isFetching: true });
    try {
      const nextPage = current.page + 1;
      const { data } = await PipelinesAPI.getBoardItems(pipelineId, {
        stage_id: stageId,
        page: nextPage,
        ...buildKanbanQueryParams(state),
      });
      commit('APPEND_STAGE_ITEMS_PAGE', {
        stageId,
        items: data.payload,
        count: data.meta.count,
        page: nextPage,
      });
    } catch {
      commit('SET_STAGE_ERROR', { stageId, hasError: true });
    } finally {
      commit('SET_STAGE_FETCHING', { stageId, isFetching: false });
    }
  },

  // Refetches page 1 of every column of the active pipeline - used on initial load, pipeline
  // switch, and (task 06) whenever a filter or sort changes. fetchStageItems never rejects (task
  // 21), so one broken column can't stop Promise.all from resolving for the rest - a single
  // aggregated alert covers however many columns came back with an error, instead of one per
  // column (which would just be noise on a flaky-network reload of the whole board).
  resetBoard: async ({ dispatch, state }) => {
    const pipelineId = state.activePipelineId;
    const stageIds = state.stageOrder[pipelineId] || [];
    await Promise.all(
      stageIds.map(stageId =>
        dispatch('fetchStageItems', { pipelineId, stageId })
      )
    );
    const failedCount = stageIds.filter(
      stageId => state.stageItems[stageId]?.hasError
    ).length;
    if (failedCount) {
      useAlert(
        i18n.global.t(
          'KANBAN.BOARD.COLUMNS_LOAD_FAILED',
          { count: failedCount },
          failedCount
        )
      );
    }
  },

  createPipeline: async ({ commit }, pipelineData) => {
    commit('SET_KANBAN_UI_FLAG', { isCreating: true });
    try {
      const { data } = await PipelinesAPI.create({ pipeline: pipelineData });
      commit('SET_PIPELINE_ITEM', data);
      return data;
    } finally {
      commit('SET_KANBAN_UI_FLAG', { isCreating: false });
    }
  },

  updatePipeline: async ({ commit }, { id, ...pipelineData }) => {
    commit('SET_KANBAN_UI_FLAG', { isUpdating: true });
    try {
      const { data } = await PipelinesAPI.update(id, {
        pipeline: pipelineData,
      });
      commit('EDIT_PIPELINE', data);
      return data;
    } finally {
      commit('SET_KANBAN_UI_FLAG', { isUpdating: false });
    }
  },

  deletePipeline: async ({ commit }, pipelineId) => {
    commit('SET_KANBAN_UI_FLAG', { isDeleting: true });
    try {
      await PipelinesAPI.delete(pipelineId);
      commit('DELETE_PIPELINE', pipelineId);
    } finally {
      commit('SET_KANBAN_UI_FLAG', { isDeleting: false });
    }
  },

  createStage: async ({ commit }, { pipelineId, ...stageData }) => {
    commit('SET_KANBAN_UI_FLAG', { isCreating: true });
    try {
      const { data } = await PipelinesAPI.createStage(pipelineId, {
        pipeline_stage: stageData,
      });
      commit('SET_STAGE_ITEM', { pipelineId, stage: data });
      return data;
    } finally {
      commit('SET_KANBAN_UI_FLAG', { isCreating: false });
    }
  },

  updateStage: async ({ commit }, { pipelineId, stageId, ...stageData }) => {
    commit('SET_KANBAN_UI_FLAG', { isUpdating: true });
    try {
      const { data } = await PipelinesAPI.updateStage(pipelineId, stageId, {
        pipeline_stage: stageData,
      });
      commit('EDIT_STAGE', data);
      return data;
    } finally {
      commit('SET_KANBAN_UI_FLAG', { isUpdating: false });
    }
  },

  deleteStage: async ({ commit }, { pipelineId, stageId }) => {
    commit('SET_KANBAN_UI_FLAG', { isDeleting: true });
    try {
      await PipelinesAPI.deleteStage(pipelineId, stageId);
      commit('DELETE_STAGE', { pipelineId, stageId });
    } finally {
      commit('SET_KANBAN_UI_FLAG', { isDeleting: false });
    }
  },

  createItem: async ({ commit }, itemData) => {
    commit('SET_KANBAN_UI_FLAG', { isCreating: true });
    try {
      const { data } = await PipelineItemsAPI.create({
        pipeline_item: itemData,
      });
      commit('SET_ITEM', data);
      return data;
    } catch (error) {
      throwErrorMessage(error);
      return null;
    } finally {
      commit('SET_KANBAN_UI_FLAG', { isCreating: false });
    }
  },

  updateItem: async ({ commit }, { id, ...itemData }) => {
    commit('SET_KANBAN_UI_FLAG', { isUpdating: true });
    try {
      const { data } = await PipelineItemsAPI.update(id, {
        pipeline_item: itemData,
      });
      commit('EDIT_ITEM', data);
      return data;
    } finally {
      commit('SET_KANBAN_UI_FLAG', { isUpdating: false });
    }
  },

  deleteItem: async ({ commit, state }, itemId) => {
    commit('SET_KANBAN_UI_FLAG', { isDeleting: true });
    try {
      const item = state.items[itemId];
      await PipelineItemsAPI.delete(itemId);
      commit('DELETE_ITEM', {
        stageId: item?.pipeline_stage_id,
        itemId,
      });
    } finally {
      commit('SET_KANBAN_UI_FLAG', { isDeleting: false });
    }
  },

  // Both drag-and-drop (KanbanBoard.handleCardMove) and manual edit
  // (KanbanCardDetail.handleSave) dispatch this directly, so the lost-reason prompt lives
  // here rather than in either caller. The commit below already moves the card optimistically
  // (vuedraggable has already moved it visually too) - if the destination is a `lost` stage
  // and no reason was pre-supplied, pause for a reason before persisting. Cancelling reuses
  // the exact same rollback commit as an API error, which the callers' `watch(storeItems...)`
  // already resyncs from.
  // `position` is expected to already be absolute within the destination stage (not a
  // page-local index) - translating a drop's visual index into that absolute position is the
  // caller's job (task 06), since it depends on exactly which pages are loaded there.
  // Returns true only when the move was actually persisted; false when the user cancelled the
  // lost-reason prompt or the API call failed. Both failure paths already rolled back and (for
  // the API error) alerted, so a caller acting on `false` should stay silent and just not
  // report success - KanbanCardDetail.handleSave depends on this to avoid claiming a save that
  // did not happen. Drag-and-drop ignores the return value, which is fine: the board's own
  // state is already correct either way.
  moveItem: async (
    { commit, state },
    { itemId, fromStageId, toStageId, position, pipelineLostReasonId = null }
  ) => {
    // Read before the optimistic commit below moves it - the rollback puts the card back at this
    // index (task 28), not at the top of the source column.
    const originalIndex = Math.max(
      0,
      state.stageItems[fromStageId]?.ids.indexOf(itemId) ?? 0
    );
    commit('MOVE_ITEM', { itemId, fromStageId, toStageId, position });

    const rollback = () => {
      commit('MOVE_ITEM', {
        itemId,
        fromStageId: toStageId,
        toStageId: fromStageId,
        position: originalIndex,
      });
    };

    let reasonId = pipelineLostReasonId;
    if (state.stages[toStageId]?.stage_type === 'lost' && !reasonId) {
      const { promptForLostReason } = useLostReasonPrompt();
      reasonId = await promptForLostReason();
      if (!reasonId) {
        rollback();
        return false;
      }
    }

    try {
      const { data } = await PipelineItemsAPI.update(itemId, {
        pipeline_item: {
          pipeline_stage_id: toStageId,
          position,
          ...(reasonId ? { pipeline_lost_reason_id: reasonId } : {}),
        },
      });
      commit('EDIT_ITEM', data);
      return true;
    } catch {
      rollback();
      useAlert(i18n.global.t('KANBAN.BOARD.MOVE_ITEM_FAILED'));
      return false;
    }
  },

  reorderStages: async ({ commit }, { pipelineId, orderedIds }) => {
    commit('REORDER_STAGES', { pipelineId, orderedIds });
    try {
      await PipelinesAPI.reorderStages(pipelineId, orderedIds);
    } catch {
      useAlert(i18n.global.t('KANBAN.BOARD.REORDER_STAGES_FAILED'));
    }
  },

  // startPosition is the offset of the page being reordered (0 for the first page) - the
  // caller (task 06) is responsible for knowing which page's cards orderedIds represents.
  reorderItems: async (
    { commit },
    { stageId, orderedIds, startPosition = 0 }
  ) => {
    commit('REORDER_ITEMS', { stageId, orderedIds });
    try {
      await PipelineItemsAPI.reorder(stageId, orderedIds, startPosition);
    } catch {
      useAlert(i18n.global.t('KANBAN.BOARD.REORDER_ITEMS_FAILED'));
    }
  },

  fetchItemLabels: async ({ commit }, itemId) => {
    const { data } = await PipelineItemLabelsAPI.get(itemId);
    commit('EDIT_ITEM', { id: itemId, label_list: data.payload });
    return data.payload;
  },

  updateItemLabels: async ({ commit }, { itemId, labels }) => {
    const { data } = await PipelineItemLabelsAPI.update(itemId, labels);
    commit('EDIT_ITEM', { id: itemId, label_list: data.payload });
    return data.payload;
  },

  exportItem: async (
    { commit, state },
    { itemId, targetPipelineId, targetStageId }
  ) => {
    commit('SET_KANBAN_UI_FLAG', { isExporting: true });
    try {
      const item = state.items[itemId];
      const { data } = await PipelineItemsAPI.export(itemId, {
        targetPipelineId,
        targetStageId,
      });
      commit('DELETE_ITEM', { stageId: item?.pipeline_stage_id, itemId });
      return data;
    } finally {
      commit('SET_KANBAN_UI_FLAG', { isExporting: false });
    }
  },

  fetchItemsForContact: async ({ commit }, contactId) => {
    const { data } = await PipelineItemsAPI.getByContact(contactId);
    data.forEach(item => commit('SET_ITEM_DATA', item));
    return data;
  },

  fetchItemsForConversation: async ({ commit }, conversationId) => {
    const { data } = await PipelineItemsAPI.getByConversation(conversationId);
    data.forEach(item => commit('SET_ITEM_DATA', item));
    return data;
  },

  // Applies a pipeline_item.created/pipeline_item.updated ActionCable push. Both events map to
  // this same handler (see actionCable.js), so it can't tell a create from an update - the
  // three cases below are decided explicitly (task 05, risk 3 - "ActionCable"):
  //
  //   - item already loaded here: if it no longer matches the active filters (e.g. assignee
  //     changed away from the one being filtered on), drop it from its (loaded) stage's
  //     list/count - it still exists, just not in this filtered view. Otherwise update its
  //     fields, and if it changed stage, move it between the two loaded lists (adjusting both
  //     counts) at the slot the card's `position` gives it (task 28, see realtimeInsertIndex) -
  //     or, when that slot can't be known, out of the old list and into the new stage's count
  //     as an unloaded card.
  //   - item not loaded (created elsewhere, or sitting on a page this column hasn't fetched):
  //     never insert it into a list - only reconcile the destination stage's count, idempotently
  //     per id (task 18: a bulk macro can push several updates for the same unloaded card, and
  //     naively adding 1 every time inflates the badge - SET_UNLOADED_ITEM_COUNTED tracks which
  //     unloaded ids are currently counted so the same transition can't apply twice, and also so
  //     a create's REST response racing in after this push doesn't double-count it, see SET_ITEM).
  //     It appears once the agent scrolls to/refetches that page.
  //     If this is an update that moved an unloaded item OUT of another stage, that source
  //     stage's count is given back too (task 27), from two sources: the stages already counting
  //     this id (SET_UNLOADED_ITEM_COUNTED tracks them), and the `previous_pipeline_stage_id` the
  //     updated push carries (ActionCableListener#pipeline_item_updated) for a card no push had
  //     been seen for. Remaining, accepted gaps: (a) with a filter active, the previous stage is
  //     not trusted (see below), so only the tracked path applies; (b) a `pipeline_item.created`
  //     for a card that left its stage before this client saw it has no previous stage. Both
  //     self-heal on the next page-1 fetch of that stage (count always comes fresh from
  //     meta.count there).
  applyRealtimePipelineItem: ({ commit, state, rootGetters }, item) => {
    if (state.activePipelineId !== item.pipeline_id) return;

    const currentUserId = rootGetters.getCurrentUserID;
    const stillMatches = itemMatchesActiveFilters(state, item, currentUserId);
    const existingItem = state.items[item.id];

    if (!existingItem) {
      // With a filter active, whether the card was in the previous stage's count depends on how
      // it matched *before* this change, which the payload doesn't carry - so the previous stage
      // is only trusted when the column is unfiltered (every card counts).
      const isFiltered = Object.keys(buildKanbanQueryParams(state)).length > 2;
      commit('SET_UNLOADED_ITEM_COUNTED', {
        stageId: item.pipeline_stage_id,
        itemId: item.id,
        counted: stillMatches,
        previousStageId: isFiltered ? null : item.previous_pipeline_stage_id,
      });
      return;
    }

    const oldStageId = existingItem.pipeline_stage_id;
    if (!stillMatches) {
      commit('REMOVE_STAGE_ITEM', { stageId: oldStageId, itemId: item.id });
      commit('EDIT_ITEM', item);
      return;
    }

    if (oldStageId !== item.pipeline_stage_id) {
      const fromStage = state.stageItems[oldStageId];
      const loadedInFrom = fromStage?.ids.includes(item.id);
      const trackedInFrom = fromStage?.unloadedCountedIds.includes(item.id);
      const insertIndex =
        loadedInFrom || trackedInFrom ? realtimeInsertIndex(state, item) : null;
      const countAsUnloaded = () =>
        commit('SET_UNLOADED_ITEM_COUNTED', {
          stageId: item.pipeline_stage_id,
          itemId: item.id,
          counted: true,
        });

      if (loadedInFrom && insertIndex !== null) {
        commit('MOVE_ITEM', {
          itemId: item.id,
          fromStageId: oldStageId,
          toStageId: item.pipeline_stage_id,
          position: insertIndex,
        });
      } else if (loadedInFrom) {
        // Can't be placed in the new stage's loaded list (see realtimeInsertIndex): leave the old
        // list and count it as unloaded over there.
        commit('REMOVE_STAGE_ITEM', { stageId: oldStageId, itemId: item.id });
        countAsUnloaded();
      } else if (trackedInFrom && insertIndex !== null) {
        // Only a count in its old stage (an earlier push put it there), but the new stage's
        // loaded list does have room for it.
        commit('SET_UNLOADED_ITEM_COUNTED', {
          stageId: oldStageId,
          itemId: item.id,
          counted: false,
        });
        commit('INSERT_STAGE_ITEM', {
          stageId: item.pipeline_stage_id,
          itemId: item.id,
          position: insertIndex,
        });
      } else if (trackedInFrom) {
        // Still can't be placed - SET_UNLOADED_ITEM_COUNTED hands the count from the old stage
        // over to the new one.
        countAsUnloaded();
      } else {
        // Neither list nor count tracks it in the old stage (e.g. only loaded by an
        // Opportunities panel), so there's nothing to move - MOVE_ITEM just updates its stage id.
        commit('MOVE_ITEM', {
          itemId: item.id,
          fromStageId: oldStageId,
          toStageId: item.pipeline_stage_id,
          position: 0,
        });
      }
    }
    commit('EDIT_ITEM', item);
  },
};
