/* global axios */
import ApiClient from './ApiClient';

class PipelineMembersAPI extends ApiClient {
  constructor() {
    super('pipelines', { accountScoped: true });
  }

  get(pipelineId) {
    return axios.get(`${this.url}/${pipelineId}/pipeline_members`);
  }

  create({ pipelineId, agentIds }) {
    return axios.post(`${this.url}/${pipelineId}/pipeline_members`, {
      user_ids: agentIds,
    });
  }

  update({ pipelineId, agentIds }) {
    return axios.patch(`${this.url}/${pipelineId}/pipeline_members`, {
      user_ids: agentIds,
    });
  }
}

export default new PipelineMembersAPI();
