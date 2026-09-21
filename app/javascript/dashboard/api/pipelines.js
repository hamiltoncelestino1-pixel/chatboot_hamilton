/* global axios */
import ApiClient from './ApiClient';

class PipelinesAPI extends ApiClient {
  constructor() {
    super('pipelines', { accountScoped: true });
  }

  getWithStages(id) {
    return axios.get(`${this.url}/${id}`);
  }

  reorderStages(pipelineId, orderedIds) {
    return axios.post(`${this.url}/${pipelineId}/pipeline_stages/reorder`, {
      ordered_ids: orderedIds,
    });
  }

  // Paginated/filtered/sorted board column (task 03) - params always includes stage_id.
  getBoardItems(pipelineId, params) {
    return axios.get(`${this.url}/${pipelineId}/pipeline_items`, { params });
  }

  createStage(pipelineId, data) {
    return axios.post(`${this.url}/${pipelineId}/pipeline_stages`, data);
  }

  updateStage(pipelineId, stageId, data) {
    return axios.patch(
      `${this.url}/${pipelineId}/pipeline_stages/${stageId}`,
      data
    );
  }

  deleteStage(pipelineId, stageId) {
    return axios.delete(`${this.url}/${pipelineId}/pipeline_stages/${stageId}`);
  }
}

export default new PipelinesAPI();
