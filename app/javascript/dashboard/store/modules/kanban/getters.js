export const getters = {
  getPipelines: $state =>
    $state.pipelineOrder.map(id => $state.pipelines[id]).filter(Boolean),

  getActivePipeline: $state =>
    $state.pipelines[$state.activePipelineId] || null,

  getStagesForPipeline: $state => pipelineId =>
    ($state.stageOrder[pipelineId] || [])
      .map(id => $state.stages[id])
      .filter(Boolean),

  getItemsForStage: $state => stageId =>
    ($state.itemOrder[stageId] || [])
      .map(id => $state.items[id])
      .filter(Boolean),

  getUIFlags: $state => $state.uiFlags,

  getItemsForContact: $state => contactId =>
    Object.values($state.items).filter(i => i.contact?.id === contactId),

  getItemsForConversation: $state => conversationId =>
    Object.values($state.items).filter(
      i => i.conversation_id === conversationId
    ),
};
