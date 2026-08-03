/* global axios */
import ApiClient from './ApiClient';

class MacrosAPI extends ApiClient {
  constructor() {
    super('macros', { accountScoped: true });
  }

  executeMacro({ macroId, conversationIds, pipelineItemIds }) {
    const payload = pipelineItemIds
      ? { pipeline_item_ids: pipelineItemIds }
      : { conversation_ids: conversationIds };
    return axios.post(`${this.url}/${macroId}/execute`, payload);
  }
}

export default new MacrosAPI();
