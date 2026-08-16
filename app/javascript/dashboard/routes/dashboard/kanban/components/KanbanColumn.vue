<script setup>
import { ref, computed, watch } from 'vue';
import draggable from 'vuedraggable';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import KanbanCard from './KanbanCard.vue';
import KanbanRunMacroMenu from './KanbanRunMacroMenu.vue';

const props = defineProps({
  stage: { type: Object, required: true },
});

const emit = defineEmits(['card-click', 'cardMove', 'add-item', 'export']);

const { t } = useI18n();
const store = useStore();
const getFilteredSortedItemsForStage = useMapGetter(
  'kanban/getFilteredSortedItemsForStage'
);
const currentUser = useMapGetter('getCurrentUser');
const isSortActive = useMapGetter('kanban/isSortActive');

const storeItems = computed(() =>
  getFilteredSortedItemsForStage.value(props.stage.id, currentUser.value?.id)
);
const localItems = ref([...storeItems.value]);

watch(storeItems, val => {
  localItems.value = [...val];
});

const onAdd = ({ item, newIndex }) => {
  const itemId = Number(item.dataset.id);
  const fromStageId = item.dataset.stageId
    ? Number(item.dataset.stageId)
    : null;
  if (fromStageId === props.stage.id) return;
  emit('cardMove', {
    itemId,
    fromStageId,
    toStageId: props.stage.id,
    position: newIndex,
  });
};

const onEnd = ({ from, to }) => {
  if (from !== to) return;
  if (isSortActive.value) {
    localItems.value = [...storeItems.value];
    return;
  }
  const orderedIds = localItems.value.map(i => i.id);
  store.dispatch('kanban/reorderItems', {
    stageId: props.stage.id,
    orderedIds,
  });
};
</script>

<template>
  <div
    class="flex flex-col w-72 flex-shrink-0 rounded-lg bg-slate-50 dark:bg-slate-800/60"
  >
    <div
      class="stage-handle flex items-center justify-between px-3 py-2.5 rounded-t-lg cursor-grab select-none flex-shrink-0"
      :style="{ borderTop: `3px solid ${stage.color || '#1f93ff'}` }"
    >
      <div class="flex items-center gap-2 min-w-0">
        <span
          class="text-sm font-semibold text-slate-700 dark:text-slate-200 truncate"
          :title="
            isSortActive ? t('KANBAN.FILTER.DISABLE_DRAG_HINT') : undefined
          "
        >
          {{ stage.name }}
        </span>
        <span
          class="flex-shrink-0 text-xs text-slate-400 bg-slate-200 dark:bg-slate-700 rounded-full px-1.5 py-0.5"
        >
          {{ localItems.length }}
        </span>
      </div>
      <div class="flex items-center gap-1 flex-shrink-0">
        <KanbanRunMacroMenu
          v-if="localItems.length"
          :pipeline-item-ids="localItems.map(item => item.id)"
          button-class="p-0.5 text-slate-400 hover:text-slate-600 dark:hover:text-slate-200 transition-colors"
        />
        <button
          class="text-slate-400 hover:text-slate-600 dark:hover:text-slate-200 transition-colors"
          @click="emit('add-item', stage.id)"
        >
          <span class="i-lucide-plus size-4" />
        </button>
      </div>
    </div>

    <draggable
      v-model="localItems"
      group="kanban-items"
      item-key="id"
      class="flex flex-col gap-2 p-2 min-h-[120px] flex-1 overflow-y-auto"
      ghost-class="kanban-ghost"
      :animation="150"
      @add="onAdd"
      @end="onEnd"
    >
      <template #item="{ element: item }">
        <KanbanCard
          :item="item"
          :data-id="item.id"
          :data-stage-id="stage.id"
          @click="emit('card-click', item)"
          @export="item => emit('export', item)"
        />
      </template>
    </draggable>

    <button
      class="mx-2 mb-2 py-1.5 text-sm text-slate-400 hover:text-slate-600 dark:hover:text-slate-300 hover:bg-slate-100 dark:hover:bg-slate-700 rounded-md transition-colors"
      @click="emit('add-item', stage.id)"
    >
      + {{ t('KANBAN.ITEM.ADD') }}
    </button>
  </div>
</template>

<style scoped>
.kanban-ghost {
  opacity: 0.4;
}
</style>
