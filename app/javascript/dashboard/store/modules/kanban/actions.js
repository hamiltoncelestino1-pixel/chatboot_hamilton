import PipelinesAPI from 'dashboard/api/pipelines';
import PipelineItemsAPI from 'dashboard/api/pipelineItems';
import PipelineItemLabelsAPI from 'dashboard/api/pipelineItemLabels';
import { useAlert } from 'dashboard/composables';

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

  moveItem: async (
    { commit },
    { itemId, fromStageId, toStageId, position }
  ) => {
    commit('MOVE_ITEM', { itemId, fromStageId, toStageId, position });
    try {
      await PipelineItemsAPI.update(itemId, {
        pipeline_item: { pipeline_stage_id: toStageId, position },
      });
    } catch {
      commit('MOVE_ITEM', {
        itemId,
        fromStageId: toStageId,
        toStageId: fromStageId,
        position: 0,
      });
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
};
