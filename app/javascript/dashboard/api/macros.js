/* global axios */
import ApiClient from './ApiClient';

class MacrosAPI extends ApiClient {
  constructor() {
    super('macros', { accountScoped: true });
  }

  executeMacro({
    macroId,
    conversationIds,
    pipelineItemIds,
    stageId,
    filters,
  }) {
    let payload;
    if (stageId) {
      // Run on every card currently matching the column's filters, resolved server-side at
      // execution time (task 07) - not the list of ids the client happened to have loaded.
      payload = { stage_id: stageId, ...filters };
    } else if (pipelineItemIds) {
      payload = { pipeline_item_ids: pipelineItemIds };
    } else {
      payload = { conversation_ids: conversationIds };
    }
    return axios.post(`${this.url}/${macroId}/execute`, payload);
  }
}

export default new MacrosAPI();
