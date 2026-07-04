import { getters } from './getters';
import { actions } from './actions';
import mutations from './mutations';

const state = {
  pipelines: {},
  stages: {},
  items: {},
  pipelineOrder: [],
  stageOrder: {},
  itemOrder: {},
  activePipelineId: null,
  uiFlags: {
    isFetchingPipelines: false,
    isFetchingItems: false,
    isCreating: false,
    isUpdating: false,
    isDeleting: false,
  },
};

export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};
