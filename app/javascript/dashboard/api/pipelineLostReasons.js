import ApiClient from './ApiClient';

class PipelineLostReasonsAPI extends ApiClient {
  constructor() {
    super('pipeline_lost_reasons', { accountScoped: true });
  }
}

export default new PipelineLostReasonsAPI();
