/* global axios */
import ApiClient from './ApiClient';

class TasksAPI extends ApiClient {
  constructor() {
    super('tasks', { accountScoped: true });
  }

  getByContact(contactId) {
    return axios.get(this.url, { params: { contact_id: contactId } });
  }

  getByConversation(conversationId) {
    return axios.get(this.url, { params: { conversation_id: conversationId } });
  }

  getByPipelineItem(pipelineItemId) {
    return axios.get(this.url, {
      params: { pipeline_item_id: pipelineItemId },
    });
  }

  complete(taskId) {
    return axios.patch(`${this.url}/${taskId}/complete`);
  }
}

export default new TasksAPI();
