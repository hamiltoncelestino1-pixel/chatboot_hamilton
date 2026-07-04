import PipelineMembersAPI from '../../api/pipelineMembers';

export const SET_PIPELINE_MEMBERS_UI_FLAG = 'SET_PIPELINE_MEMBERS_UI_FLAG';
export const SET_PIPELINE_MEMBERS = 'SET_PIPELINE_MEMBERS';

export const state = {
  records: {},
  uiFlags: {
    isFetching: false,
    isCreating: false,
    isUpdating: false,
  },
};

export const getters = {
  getUIFlags(_state) {
    return _state.uiFlags;
  },
  getPipelineMembers: $state => pipelineId => {
    return $state.records[pipelineId] || [];
  },
};

export const actions = {
  get: async ({ commit }, { pipelineId }) => {
    commit(SET_PIPELINE_MEMBERS_UI_FLAG, { isFetching: true });
    try {
      const { data } = await PipelineMembersAPI.get(pipelineId);
      commit(SET_PIPELINE_MEMBERS, { pipelineId, data });
    } finally {
      commit(SET_PIPELINE_MEMBERS_UI_FLAG, { isFetching: false });
    }
  },
  create: async ({ commit }, { pipelineId, agentIds }) => {
    commit(SET_PIPELINE_MEMBERS_UI_FLAG, { isCreating: true });
    try {
      const { data } = await PipelineMembersAPI.create({
        pipelineId,
        agentIds,
      });
      commit(SET_PIPELINE_MEMBERS, { pipelineId, data });
    } finally {
      commit(SET_PIPELINE_MEMBERS_UI_FLAG, { isCreating: false });
    }
  },
  update: async ({ commit }, { pipelineId, agentIds }) => {
    commit(SET_PIPELINE_MEMBERS_UI_FLAG, { isUpdating: true });
    try {
      const { data } = await PipelineMembersAPI.update({
        pipelineId,
        agentIds,
      });
      commit(SET_PIPELINE_MEMBERS, { pipelineId, data });
    } finally {
      commit(SET_PIPELINE_MEMBERS_UI_FLAG, { isUpdating: false });
    }
  },
};

export const mutations = {
  [SET_PIPELINE_MEMBERS_UI_FLAG]($state, data) {
    $state.uiFlags = { ...$state.uiFlags, ...data };
  },
  [SET_PIPELINE_MEMBERS]($state, { pipelineId, data }) {
    $state.records = { ...$state.records, [pipelineId]: data };
  },
};

export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};
