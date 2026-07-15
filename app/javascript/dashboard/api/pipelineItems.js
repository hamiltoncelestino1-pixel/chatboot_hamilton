/* global axios */
import ApiClient from './ApiClient';

class PipelineItemsAPI extends ApiClient {
  constructor() {
    super('pipeline_items', { accountScoped: true });
  }

  reorder(stageId, orderedIds) {
    return axios.post(`${this.url}/reorder`, {
      stage_id: stageId,
      ordered_ids: orderedIds,
    });
  }

  getByContact(contactId) {
    return axios.get(this.url, { params: { contact_id: contactId } });
  }

  getByConversation(conversationId) {
    return axios.get(this.url, { params: { conversation_id: conversationId } });
  }

  export(itemId, { targetPipelineId, targetStageId }) {
    return axios.post(`${this.url}/${itemId}/export`, {
      pipeline_item: {
        target_pipeline_id: targetPipelineId,
        target_stage_id: targetStageId,
      },
    });
  }
}

export default new PipelineItemsAPI();
