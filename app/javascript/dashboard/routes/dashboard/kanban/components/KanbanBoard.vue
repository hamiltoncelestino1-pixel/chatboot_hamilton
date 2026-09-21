<script setup>
import { ref, computed, watch, provide } from 'vue';
import draggable from 'vuedraggable';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import KanbanColumn from './KanbanColumn.vue';

const emit = defineEmits(['card-click', 'add-item', 'export']);

const store = useStore();
const activePipeline = useMapGetter('kanban/getActivePipeline');
const getStagesForPipeline = useMapGetter('kanban/getStagesForPipeline');

// Same for every card on the board, so it's computed once here instead of once per card
// (KanbanCard.vue used to call this per instance - task 09). Pre-filtered to display_on_card
// since that filter doesn't depend on the card either, only the value read from it does.
const cardAttributeDefinitions = useMapGetter(
  'attributes/getAttributesByModel'
);
const visibleCardAttributeDefinitions = computed(() =>
  cardAttributeDefinitions
    .value('pipeline_item_attribute')
    .filter(attr => attr.display_on_card)
);
provide('kanbanCardAttributeDefinitions', visibleCardAttributeDefinitions);

const storeStages = computed(() =>
  activePipeline.value
    ? getStagesForPipeline.value(activePipeline.value.id)
    : []
);

const localStages = ref([...storeStages.value]);

watch(storeStages, val => {
  localStages.value = [...val];
});

const onStagesDragEnd = async ({ newIndex, oldIndex }) => {
  if (newIndex === oldIndex) return;
  const orderedIds = localStages.value.map(s => s.id);
  await store.dispatch('kanban/reorderStages', {
    pipelineId: activePipeline.value.id,
    orderedIds,
  });
};

const handleCardMove = async ({ itemId, fromStageId, toStageId, position }) => {
  await store.dispatch('kanban/moveItem', {
    itemId,
    fromStageId,
    toStageId,
    position,
  });
};
</script>

<template>
  <div class="flex flex-1 min-h-0 overflow-x-auto gap-4 p-4">
    <draggable
      v-model="localStages"
      group="kanban-stages"
      item-key="id"
      class="flex gap-4"
      handle=".stage-handle"
      ghost-class="kanban-stage-ghost"
      :animation="200"
      @end="onStagesDragEnd"
    >
      <template #item="{ element: stage }">
        <KanbanColumn
          :stage="stage"
          @card-click="item => emit('card-click', item)"
          @card-move="handleCardMove"
          @add-item="stageId => emit('add-item', stageId)"
          @export="item => emit('export', item)"
        />
      </template>
    </draggable>
  </div>
</template>

<style scoped>
.kanban-stage-ghost {
  opacity: 0.4;
}
</style>
