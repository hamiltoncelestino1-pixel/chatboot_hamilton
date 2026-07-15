<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useToggle } from '@vueuse/core';
import { vOnClickOutside } from '@vueuse/components';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useUISettings } from 'dashboard/composables/useUISettings';
import NextButton from 'dashboard/components-next/button/Button.vue';
import SelectMenu from 'dashboard/components-next/selectmenu/SelectMenu.vue';

const { t } = useI18n();
const store = useStore();
const { setKanbanBoardSettings } = useUISettings();

const [isOpen, toggleOpen] = useToggle();

const activePipeline = useMapGetter('kanban/getActivePipeline');
const activeSort = useMapGetter('kanban/getActiveSort');
const isSortActive = useMapGetter('kanban/isSortActive');

const sortMenus = computed(() => [
  { label: t('KANBAN.SORT.OPTIONS.ASSIGNEE'), value: 'assignee' },
  { label: t('KANBAN.SORT.OPTIONS.CREATED_AT'), value: 'created_at' },
  { label: t('KANBAN.SORT.OPTIONS.UPDATED_AT'), value: 'updated_at' },
  { label: t('KANBAN.SORT.OPTIONS.VALUE'), value: 'value' },
]);

const orderingMenus = computed(() => [
  { label: t('KANBAN.SORT.ORDER.ASC'), value: 'asc' },
  { label: t('KANBAN.SORT.ORDER.DESC'), value: 'desc' },
]);

const activeSortLabel = computed(
  () =>
    sortMenus.value.find(m => m.value === activeSort.value.field)?.label || ''
);
const activeOrderingLabel = computed(
  () =>
    orderingMenus.value.find(m => m.value === activeSort.value.order)?.label ||
    ''
);

const persist = sort => {
  if (!activePipeline.value) return;
  setKanbanBoardSettings(activePipeline.value.id, { sort });
};

const handleSortChange = field => {
  const sort = { field, order: activeSort.value.order };
  store.commit('kanban/SET_KANBAN_SORT', sort);
  persist(sort);
};

const handleOrderChange = order => {
  const sort = { field: activeSort.value.field, order };
  store.commit('kanban/SET_KANBAN_SORT', sort);
  persist(sort);
};
</script>

<template>
  <div class="relative flex">
    <NextButton
      v-tooltip.right="t('KANBAN.SORT.TOOLTIP')"
      icon="i-lucide-arrow-up-down"
      slate
      faded
      xs
      @click="toggleOpen()"
    />
    <span
      v-if="isSortActive"
      class="absolute top-0 right-0 size-1.5 rounded-full bg-woot-500 pointer-events-none"
    />
    <div
      v-if="isOpen"
      v-on-click-outside="() => toggleOpen()"
      class="mt-1 bg-white dark:bg-slate-800 border border-slate-200 dark:border-slate-600 shadow-lg w-72 rounded-xl p-4 absolute z-40 top-full ltr:right-0 rtl:left-0 flex flex-col gap-4"
    >
      <div class="flex items-center justify-between gap-2">
        <span class="text-sm truncate text-n-slate-12">{{
          t('KANBAN.SORT.FIELD_LABEL')
        }}</span>
        <SelectMenu
          :model-value="activeSort.field"
          :options="sortMenus"
          :label="activeSortLabel"
          @update:model-value="handleSortChange"
        />
      </div>
      <div class="flex items-center justify-between gap-2">
        <span class="text-sm truncate text-n-slate-12">{{
          t('KANBAN.SORT.ORDER_LABEL')
        }}</span>
        <SelectMenu
          :model-value="activeSort.order"
          :options="orderingMenus"
          :label="activeOrderingLabel"
          @update:model-value="handleOrderChange"
        />
      </div>
    </div>
  </div>
</template>
