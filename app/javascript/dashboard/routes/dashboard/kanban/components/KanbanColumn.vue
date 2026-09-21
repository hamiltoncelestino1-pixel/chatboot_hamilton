<script setup>
import { ref, computed, watch } from 'vue';
import draggable from 'vuedraggable';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import IntersectionObserver from 'dashboard/components/IntersectionObserver.vue';
import KanbanCard from './KanbanCard.vue';
import KanbanRunMacroMenu from './KanbanRunMacroMenu.vue';

const props = defineProps({
  stage: { type: Object, required: true },
});

const emit = defineEmits(['card-click', 'cardMove', 'add-item', 'export']);

const { t } = useI18n();
const store = useStore();
const getItemsForStage = useMapGetter('kanban/getItemsForStage');
const getStageItemsMeta = useMapGetter('kanban/getStageItemsMeta');
const isSortActive = useMapGetter('kanban/isSortActive');

// count/hasMore/isFetching come from the server (task 05) - not derived from how many cards
// happen to be loaded, so the badge and the end-of-list state stay correct under pagination.
const stageMeta = computed(() => getStageItemsMeta.value(props.stage.id));

// Already filtered/ordered server-side (task 03) - no client-side re-filter/re-sort needed
// (task 08).
const storeItems = computed(() => getItemsForStage.value(props.stage.id));
const localItems = ref([...storeItems.value]);

watch(storeItems, val => {
  localItems.value = [...val];
});

const draggableEl = ref(null);
const intersectionObserverOptions = computed(() => ({
  root: draggableEl.value?.$el,
  rootMargin: '100px 0px 100px 0px',
}));

const loadMoreItems = () => {
  store.dispatch('kanban/fetchMoreStageItems', {
    pipelineId: props.stage.pipeline_id,
    stageId: props.stage.id,
  });
};

// Retries whichever fetch actually failed (task 21): page 1 if nothing loaded yet, otherwise
// the next page - same distinction the template makes to decide which error state to show.
const retryLoad = () => {
  if (localItems.value.length) {
    loadMoreItems();
  } else {
    store.dispatch('kanban/fetchStageItems', {
      pipelineId: props.stage.pipeline_id,
      stageId: props.stage.id,
    });
  }
};

// `newIndex` is the drop index within localItems, which mirrors the stage's full accumulated
// loaded prefix (every page fetched so far - task 05's stageItems.ids), not just one page. Pages
// load in position order starting at 0, so that index already *is* the right absolute position -
// except when dropping at the very end of a column that still has more pages below (hasMore),
// where it's only an approximation of "last loaded", not "last in the stage". Chosen behavior
// (task 06, risk 2 - the simplest of the documented options): accept the approximation. The card
// keeps the position it was dropped at, and the column re-sorts itself once the next page loads
// and reveals where it actually falls relative to the still-unloaded cards.
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
          {{ stageMeta.count }}
        </span>
      </div>
      <div class="flex items-center gap-1 flex-shrink-0">
        <KanbanRunMacroMenu
          v-if="stageMeta.count"
          :stage-id="stage.id"
          :item-count="stageMeta.count"
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

    <div
      v-if="stageMeta.isFetching && !localItems.length"
      class="flex flex-1 items-center justify-center min-h-[120px]"
    >
      <Spinner class="text-woot-500" />
    </div>
    <!-- Distinct from a legitimately empty column (stageMeta.hasError is false there) - task 21. -->
    <div
      v-else-if="stageMeta.hasError && !localItems.length"
      class="flex flex-1 flex-col items-center justify-center min-h-[120px] gap-1.5 px-3 text-center"
    >
      <span class="i-lucide-alert-triangle size-4 text-slate-400" />
      <p class="text-xs text-slate-400">{{ t('KANBAN.COLUMN.ERROR') }}</p>
      <button
        class="text-xs text-woot-500 hover:text-woot-600 hover:underline"
        @click="retryLoad"
      >
        {{ t('KANBAN.COLUMN.RETRY') }}
      </button>
    </div>
    <draggable
      v-else
      ref="draggableEl"
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
      <template #footer>
        <!-- flex-shrink-0: siblings are direct children of a flex-col container that's
             typically shorter than its content (that's why it scrolls) - without this,
             flexbox's default min-height:auto collapses an empty/low-content child like the
             IntersectionObserver sentinel down to 0px, and it stops intersecting anything. -->
        <div
          v-if="stageMeta.isFetching"
          class="flex flex-shrink-0 justify-center py-2"
        >
          <Spinner size="16" class="text-woot-500" />
        </div>
        <!-- "Load more" failed with cards from earlier pages already on screen - stop the
             observer from retrying in a loop (task 21) and offer an explicit retry instead. -->
        <div
          v-else-if="stageMeta.hasError"
          class="flex flex-shrink-0 flex-col items-center gap-1 py-2"
        >
          <p class="text-xs text-slate-400">{{ t('KANBAN.COLUMN.ERROR') }}</p>
          <button
            class="text-xs text-woot-500 hover:text-woot-600 hover:underline"
            @click="retryLoad"
          >
            {{ t('KANBAN.COLUMN.RETRY') }}
          </button>
        </div>
        <p
          v-else-if="!stageMeta.hasMore && stageMeta.count"
          class="flex-shrink-0 py-2 text-xs text-center text-slate-400"
        >
          {{ t('KANBAN.COLUMN.END_OF_LIST') }}
        </p>
        <IntersectionObserver
          v-else-if="stageMeta.hasMore"
          class="flex-shrink-0"
          :options="intersectionObserverOptions"
          @observed="loadMoreItems"
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
