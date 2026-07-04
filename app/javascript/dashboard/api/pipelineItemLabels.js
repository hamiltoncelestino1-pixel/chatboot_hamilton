/* global axios */
import ApiClient from './ApiClient';

class PipelineItemLabels extends ApiClient {
  constructor() {
    super('pipeline_items', { accountScoped: true });
  }

  get(itemId) {
    return axios.get(`${this.url}/${itemId}/labels`);
  }

  update(itemId, labels) {
    return axios.post(`${this.url}/${itemId}/labels`, { labels });
  }
}

export default new PipelineItemLabels();
