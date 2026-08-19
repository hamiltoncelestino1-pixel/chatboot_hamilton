/* global axios */
import ApiClient from './ApiClient';

class PipelineReportsAPI extends ApiClient {
  constructor() {
    super('pipelines', { accountScoped: true });
  }

  getFunnelReport(pipelineId) {
    return axios.get(`${this.url}/${pipelineId}/funnel_report`);
  }
}

export default new PipelineReportsAPI();
