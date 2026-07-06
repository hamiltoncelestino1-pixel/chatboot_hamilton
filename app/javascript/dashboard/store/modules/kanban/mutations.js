const mutations = {
  SET_KANBAN_UI_FLAG($state, data) {
    $state.uiFlags = { ...$state.uiFlags, ...data };
  },

  SET_PIPELINES($state, pipelines) {
    const records = {};
    const order = [];
    pipelines.forEach(p => {
      records[p.id] = p;
      order.push(p.id);
      if (p.stages) {
        p.stages.forEach(s => {
          $state.stages[s.id] = s;
        });
        $state.stageOrder[p.id] = p.stages.map(s => s.id);
      }
    });
    $state.pipelines = records;
    $state.pipelineOrder = order;
  },

  SET_PIPELINE_ITEM($state, pipeline) {
    $state.pipelines[pipeline.id] = pipeline;
    if (!$state.pipelineOrder.includes(pipeline.id)) {
      $state.pipelineOrder = [...$state.pipelineOrder, pipeline.id];
    }
    if (pipeline.stages) {
      pipeline.stages.forEach(s => {
        $state.stages[s.id] = s;
      });
      $state.stageOrder[pipeline.id] = pipeline.stages.map(s => s.id);
    }
  },

  EDIT_PIPELINE($state, pipeline) {
    $state.pipelines[pipeline.id] = {
      ...($state.pipelines[pipeline.id] || {}),
      ...pipeline,
    };
  },

  DELETE_PIPELINE($state, pipelineId) {
    const { [pipelineId]: _removed, ...remaining } = $state.pipelines;
    $state.pipelines = remaining;
    $state.pipelineOrder = $state.pipelineOrder.filter(id => id !== pipelineId);
    if ($state.activePipelineId === pipelineId) {
      $state.activePipelineId = $state.pipelineOrder[0] || null;
    }
  },

  SET_STAGES($state, { pipelineId, stages }) {
    stages.forEach(s => {
      $state.stages[s.id] = s;
    });
    $state.stageOrder[pipelineId] = stages.map(s => s.id);
  },

  SET_STAGE_ITEM($state, { pipelineId, stage }) {
    $state.stages[stage.id] = stage;
    const order = $state.stageOrder[pipelineId] || [];
    if (!order.includes(stage.id)) {
      $state.stageOrder[pipelineId] = [...order, stage.id];
    }
  },

  EDIT_STAGE($state, stage) {
    $state.stages[stage.id] = { ...($state.stages[stage.id] || {}), ...stage };
  },

  DELETE_STAGE($state, { pipelineId, stageId }) {
    const { [stageId]: _removed, ...remaining } = $state.stages;
    $state.stages = remaining;
    $state.stageOrder[pipelineId] = (
      $state.stageOrder[pipelineId] || []
    ).filter(id => id !== stageId);
  },

  SET_ITEMS($state, items) {
    items.forEach(item => {
      $state.items[item.id] = item;
      const stageId = item.pipeline_stage_id;
      const order = $state.itemOrder[stageId] || [];
      if (!order.includes(item.id)) {
        $state.itemOrder[stageId] = [...order, item.id];
      }
    });
  },

  SET_ITEM($state, item) {
    $state.items[item.id] = item;
    const stageId = item.pipeline_stage_id;
    const order = $state.itemOrder[stageId] || [];
    if (!order.includes(item.id)) {
      $state.itemOrder[stageId] = [...order, item.id];
    }
  },

  // Stores item data only — does NOT touch itemOrder (used by contact/conversation lookups
  // to avoid polluting the board's column ordering before SET_ACTIVE_PIPELINE clears it)
  SET_ITEM_DATA($state, item) {
    $state.items[item.id] = item;
  },

  EDIT_ITEM($state, item) {
    $state.items[item.id] = { ...($state.items[item.id] || {}), ...item };
  },

  DELETE_ITEM($state, { stageId, itemId }) {
    const { [itemId]: _removed, ...remaining } = $state.items;
    $state.items = remaining;
    $state.itemOrder[stageId] = ($state.itemOrder[stageId] || []).filter(
      id => id !== itemId
    );
  },

  MOVE_ITEM($state, { itemId, fromStageId, toStageId, position }) {
    $state.itemOrder[fromStageId] = (
      $state.itemOrder[fromStageId] || []
    ).filter(id => id !== itemId);
    const destOrder = [...($state.itemOrder[toStageId] || [])];
    destOrder.splice(position, 0, itemId);
    $state.itemOrder[toStageId] = destOrder;
    if ($state.items[itemId]) {
      $state.items[itemId] = {
        ...$state.items[itemId],
        pipeline_stage_id: toStageId,
      };
    }
  },

  SET_ACTIVE_PIPELINE($state, pipelineId) {
    $state.activePipelineId = pipelineId;
    $state.itemOrder = {};
  },

  REORDER_STAGES($state, { pipelineId, orderedIds }) {
    $state.stageOrder[pipelineId] = orderedIds;
  },

  REORDER_ITEMS($state, { stageId, orderedIds }) {
    $state.itemOrder[stageId] = orderedIds;
  },

  CLEAR_ITEMS($state, stageId) {
    $state.itemOrder[stageId] = [];
  },
};

export default mutations;
