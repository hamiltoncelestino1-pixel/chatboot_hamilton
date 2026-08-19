import PipelinesAPI from 'dashboard/api/pipelines';
import PipelineItemsAPI from 'dashboard/api/pipelineItems';
import PipelineItemLabelsAPI from 'dashboard/api/pipelineItemLabels';
import { useAlert } from 'dashboard/composables';
import { useLostReasonPrompt } from 'dashboard/composables/useLostReasonPrompt';
import { throwErrorMessage } from '../../utils/api';

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

  fetchItems: async ({ commit }, pipelineId) => {
    commit('SET_KANBAN_UI_FLAG', { isFetchingItems: true });
    try {
      const { data } = await PipelinesAPI.getItems(pipelineId);
      commit('SET_ITEMS', data);
    } finally {
      commit('SET_KANBAN_UI_FLAG', { isFetchingItems: false });
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
  moveItem: async (
    { commit, state },
    { itemId, fromStageId, toStageId, position, pipelineLostReasonId = null }
  ) => {
    commit('MOVE_ITEM', { itemId, fromStageId, toStageId, position });

    const rollback = () => {
      commit('MOVE_ITEM', {
        itemId,
        fromStageId: toStageId,
        toStageId: fromStageId,
        position: 0,
      });
    };

    let reasonId = pipelineLostReasonId;
    if (state.stages[toStageId]?.stage_type === 'lost' && !reasonId) {
      const { promptForLostReason } = useLostReasonPrompt();
      reasonId = await promptForLostReason();
      if (!reasonId) {
        rollback();
        return;
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
    } catch {
      rollback();
      useAlert('Failed to move card. Please try again.');
    }
  },

  reorderStages: async ({ commit }, { pipelineId, orderedIds }) => {
    commit('REORDER_STAGES', { pipelineId, orderedIds });
    try {
      await PipelinesAPI.reorderStages(pipelineId, orderedIds);
    } catch {
      useAlert('Failed to reorder stages. Please try again.');
    }
  },

  reorderItems: async ({ commit }, { stageId, orderedIds }) => {
    commit('REORDER_ITEMS', { stageId, orderedIds });
    try {
      await PipelineItemsAPI.reorder(stageId, orderedIds);
    } catch {
      useAlert('Failed to reorder cards. Please try again.');
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

  // Applies a pipeline_item.created/pipeline_item.updated ActionCable push (task 10).
  // Ignores items outside the pipeline currently open on this board - they aren't
  // rendered anywhere here, and staying quiet avoids polluting itemOrder for stages
  // that were never fetched into stageOrder.
  applyRealtimePipelineItem: ({ commit, state }, item) => {
    if (state.activePipelineId !== item.pipeline_id) return;

    const existingItem = state.items[item.id];
    if (
      existingItem &&
      existingItem.pipeline_stage_id !== item.pipeline_stage_id
    ) {
      commit('MOVE_ITEM', {
        itemId: item.id,
        fromStageId: existingItem.pipeline_stage_id,
        toStageId: item.pipeline_stage_id,
        position: 0,
      });
    }
    commit('SET_ITEM', item);
  },
};
