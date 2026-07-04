<script setup>
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';

const { t } = useI18n();
const store = useStore();
const pipelines = useMapGetter('kanban/getPipelines');
const activePipeline = useMapGetter('kanban/getActivePipeline');

const isOpen = ref(false);

const selectPipeline = async pipeline => {
  isOpen.value = false;
  store.commit('kanban/SET_ACTIVE_PIPELINE', pipeline.id);
  await store.dispatch('kanban/fetchItems', pipeline.id);
};
</script>

<template>
  <div class="relative">
    <button
      class="flex items-center gap-2 px-3 py-1.5 text-sm font-medium text-slate-700 dark:text-slate-200 bg-white dark:bg-slate-700 border border-slate-200 dark:border-slate-600 rounded-lg hover:bg-slate-50 dark:hover:bg-slate-600 transition-colors"
      @click="isOpen = !isOpen"
    >
      <span class="i-lucide-columns-3 size-4 text-slate-500" />
      <span class="max-w-[160px] truncate">
        {{ activePipeline?.name || t('KANBAN.TITLE') }}
      </span>
      <span
        class="i-lucide-chevron-down size-4 text-slate-400"
        :class="{ 'rotate-180': isOpen }"
      />
    </button>

    <div
      v-if="isOpen"
      class="absolute top-full left-0 mt-1 w-48 bg-white dark:bg-slate-800 border border-slate-200 dark:border-slate-600 rounded-lg shadow-lg z-10 py-1"
    >
      <button
        v-for="pipeline in pipelines"
        :key="pipeline.id"
        class="w-full text-left px-3 py-2 text-sm text-slate-700 dark:text-slate-200 hover:bg-slate-50 dark:hover:bg-slate-700 transition-colors"
        :class="{
          'font-semibold text-woot-600 dark:text-woot-400':
            activePipeline?.id === pipeline.id,
        }"
        @click="selectPipeline(pipeline)"
      >
        {{ pipeline.name }}
      </button>
    </div>
  </div>
</template>
