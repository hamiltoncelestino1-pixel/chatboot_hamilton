export const getters = {
  getUIFlags: $state => $state.uiFlags,
  getTasksForContact: $state => contactId =>
    Object.values($state.items).filter(t => t.contact_id === contactId),
  getTasksForConversation: $state => conversationId =>
    Object.values($state.items).filter(
      t => t.conversation_id === conversationId
    ),
  getTasksForPipelineItem: $state => pipelineItemId =>
    Object.values($state.items).filter(
      t => t.pipeline_item_id === pipelineItemId
    ),
};
