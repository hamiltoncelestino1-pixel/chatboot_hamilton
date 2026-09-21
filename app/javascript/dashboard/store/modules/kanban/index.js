import { getters } from './getters';
import { actions } from './actions';
import mutations from './mutations';
import { DEFAULT_KANBAN_FILTERS, DEFAULT_KANBAN_SORT } from './constants';

const state = {
  pipelines: {},
  stages: {},
  items: {},
  // Lookup indices into `items`, keyed by contact id / conversation id (task 10) - what
  // ContactOpportunities.vue/ConversationOpportunities.vue read through
  // getItemsForContact/getItemsForConversation, kept in sync by every mutation that writes an
  // item. { [id]: itemId[] }
  itemIdsByContact: {},
  itemIdsByConversation: {},
  pipelineOrder: [],
  stageOrder: {},
  // Paginated per-column state (task 05):
  // { [stageId]: { ids: [], page: 1, count: 0, hasMore: true, isFetching: false } }
  // count/hasMore come from the server (meta.count), not from ids.length alone.
  stageItems: {},
  activePipelineId: null,
  activeFilters: { ...DEFAULT_KANBAN_FILTERS },
  activeSort: { ...DEFAULT_KANBAN_SORT },
  showOnlyMine: false,
  uiFlags: {
    isFetchingPipelines: false,
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
