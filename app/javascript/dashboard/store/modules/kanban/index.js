import { getters } from './getters';
import { actions } from './actions';
import mutations from './mutations';
import { DEFAULT_KANBAN_FILTERS, DEFAULT_KANBAN_SORT } from './constants';

const state = {
  pipelines: {},
  stages: {},
  items: {},
  pipelineOrder: [],
  stageOrder: {},
  itemOrder: {},
  activePipelineId: null,
  activeFilters: { ...DEFAULT_KANBAN_FILTERS },
  activeSort: { ...DEFAULT_KANBAN_SORT },
  showOnlyMine: false,
  uiFlags: {
    isFetchingPipelines: false,
    isFetchingItems: false,
    isCreating: false,
    isUpdating: false,
    isDeleting: false,
    isExporting: false,
  },
};

export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};
