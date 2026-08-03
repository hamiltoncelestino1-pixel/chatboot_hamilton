<script setup>
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useDebounceFn, useToggle } from '@vueuse/core';
import { vOnClickOutside } from '@vueuse/components';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useUISettings } from 'dashboard/composables/useUISettings';
import NextButton from 'dashboard/components-next/button/Button.vue';
import LabelDropdown from 'shared/components/ui/label/LabelDropdown.vue';

const { t } = useI18n();
const store = useStore();
const { setKanbanBoardSettings } = useUISettings();

const [isOpen, toggleOpen] = useToggle();

const activePipeline = useMapGetter('kanban/getActivePipeline');
const activeFilters = useMapGetter('kanban/getActiveFilters');
const showOnlyMine = useMapGetter('kanban/getShowOnlyMine');
const isFilterActive = useMapGetter('kanban/isFilterActive');
const getPipelineMembers = useMapGetter('pipelineMembers/getPipelineMembers');
const pipelineLabels = useMapGetter('labels/getPipelineLabels');

const members = computed(() =>
  activePipeline.value ? getPipelineMembers.value(activePipeline.value.id) : []
);

const showLabelPicker = ref(false);
const toggleLabelPicker = () => {
  showLabelPicker.value = !showLabelPicker.value;
};

const selectedLabelTitles = computed(
  () => activeFilters.value.labelTitles || []
);
const selectedLabelObjects = computed(() =>
  pipelineLabels.value.filter(l => selectedLabelTitles.value.includes(l.title))
);

const persist = () => {
  if (!activePipeline.value) return;
  setKanbanBoardSettings(activePipeline.value.id, {
    filters: activeFilters.value,
    showOnlyMine: showOnlyMine.value,
  });
};

const applyFilter = patch => {
  store.commit('kanban/SET_KANBAN_FILTERS', patch);
  persist();
};

const debouncedApplyFilter = useDebounceFn(applyFilter, 500);

const toggleShowOnlyMine = value => {
  store.commit('kanban/SET_SHOW_ONLY_MINE', value);
  persist();
};

const clearFilters = () => {
  store.commit('kanban/RESET_KANBAN_FILTERS');
  store.commit('kanban/SET_SHOW_ONLY_MINE', false);
  persist();
};

const onAssigneeChange = e => {
  const raw = e.target.value;
  let assigneeId;
  if (raw === '') assigneeId = null;
  else if (raw === 'unassigned') assigneeId = 'unassigned';
  else assigneeId = Number(raw);
  applyFilter({ assigneeId });
};

const onValueMin = e => {
  const min = e.target.value ? Number(e.target.value) : null;
  debouncedApplyFilter({
    valueRange: { ...(activeFilters.value.valueRange || {}), min },
  });
};

const onValueMax = e => {
  const max = e.target.value ? Number(e.target.value) : null;
  debouncedApplyFilter({
    valueRange: { ...(activeFilters.value.valueRange || {}), max },
  });
};

const applyLabelTitles = titles => {
  applyFilter({ labelTitles: titles.length ? titles : null });
};

const onAddLabel = label => {
  if (selectedLabelTitles.value.includes(label.title)) return;
  applyLabelTitles([...selectedLabelTitles.value, label.title]);
};

const onRemoveLabel = title => {
  applyLabelTitles(
    selectedLabelTitles.value.filter(existingTitle => existingTitle !== title)
  );
};
</script>

<template>
  <div class="flex items-center gap-2">
    <!-- Sempre visível: exceção pedida pelo usuário -->
    <label
      class="flex items-center gap-1.5 text-sm text-slate-600 dark:text-slate-300 cursor-pointer select-none"
    >
      <input
        type="checkbox"
        class="rounded"
        :checked="showOnlyMine"
        @change="toggleShowOnlyMine($event.target.checked)"
      />
      {{ t('KANBAN.FILTER.SHOW_ONLY_MINE') }}
    </label>

    <div class="relative flex">
      <NextButton
        v-tooltip.right="t('KANBAN.FILTER.TOOLTIP')"
        icon="i-lucide-list-filter"
        slate
        faded
        xs
        @click="toggleOpen()"
      />
      <span
        v-if="isFilterActive"
        class="absolute top-0 right-0 size-1.5 rounded-full bg-woot-500 pointer-events-none"
      />
      <div
        v-if="isOpen"
        v-on-click-outside="() => toggleOpen()"
        class="mt-1 bg-white dark:bg-slate-800 border border-slate-200 dark:border-slate-600 shadow-lg w-80 rounded-xl p-4 absolute z-40 top-full ltr:left-0 rtl:right-0 flex flex-col gap-3"
      >
        <!-- Responsável -->
        <div class="flex flex-col gap-1">
          <span class="text-xs text-n-slate-11">{{
            t('KANBAN.FILTER.ASSIGNEE_LABEL')
          }}</span>
          <select
            :value="activeFilters.assigneeId ?? ''"
            class="text-sm rounded-md border border-slate-200 dark:border-slate-600 dark:bg-slate-700 dark:text-slate-200 px-2 py-1"
            @change="onAssigneeChange"
          >
            <option value="">{{ t('KANBAN.FILTER.ALL') }}</option>
            <option value="unassigned">
              {{ t('KANBAN.FILTER.UNASSIGNED') }}
            </option>
            <option
              v-for="member in members"
              :key="member.id"
              :value="member.id"
            >
              {{ member.name }}
            </option>
          </select>
        </div>

        <!-- Data de criação -->
        <div class="flex flex-col gap-1">
          <span class="text-xs text-n-slate-11">{{
            t('KANBAN.FILTER.CREATED_AT_LABEL')
          }}</span>
          <div class="flex items-center gap-1">
            <input
              type="date"
              :value="activeFilters.createdAtRange?.from ?? ''"
              class="flex-1 min-w-0 text-sm rounded-md border border-slate-200 dark:border-slate-600 dark:bg-slate-700 dark:text-slate-200 px-2 py-1"
              @change="
                applyFilter({
                  createdAtRange: {
                    ...(activeFilters.createdAtRange || {}),
                    from: $event.target.value || null,
                  },
                })
              "
            />
            <span class="text-xs text-slate-400">–</span>
            <input
              type="date"
              :value="activeFilters.createdAtRange?.to ?? ''"
              class="flex-1 min-w-0 text-sm rounded-md border border-slate-200 dark:border-slate-600 dark:bg-slate-700 dark:text-slate-200 px-2 py-1"
              @change="
                applyFilter({
                  createdAtRange: {
                    ...(activeFilters.createdAtRange || {}),
                    to: $event.target.value || null,
                  },
                })
              "
            />
          </div>
        </div>

        <!-- Data de atualização -->
        <div class="flex flex-col gap-1">
          <span class="text-xs text-n-slate-11">{{
            t('KANBAN.FILTER.UPDATED_AT_LABEL')
          }}</span>
          <div class="flex items-center gap-1">
            <input
              type="date"
              :value="activeFilters.updatedAtRange?.from ?? ''"
              class="flex-1 min-w-0 text-sm rounded-md border border-slate-200 dark:border-slate-600 dark:bg-slate-700 dark:text-slate-200 px-2 py-1"
              @change="
                applyFilter({
                  updatedAtRange: {
                    ...(activeFilters.updatedAtRange || {}),
                    from: $event.target.value || null,
                  },
                })
              "
            />
            <span class="text-xs text-slate-400">–</span>
            <input
              type="date"
              :value="activeFilters.updatedAtRange?.to ?? ''"
              class="flex-1 min-w-0 text-sm rounded-md border border-slate-200 dark:border-slate-600 dark:bg-slate-700 dark:text-slate-200 px-2 py-1"
              @change="
                applyFilter({
                  updatedAtRange: {
                    ...(activeFilters.updatedAtRange || {}),
                    to: $event.target.value || null,
                  },
                })
              "
            />
          </div>
        </div>

        <!-- Range de valor -->
        <div class="flex flex-col gap-1">
          <span class="text-xs text-n-slate-11">{{
            t('KANBAN.FILTER.VALUE_LABEL')
          }}</span>
          <div class="flex items-center gap-1">
            <input
              type="number"
              :placeholder="t('KANBAN.FILTER.MIN')"
              :value="activeFilters.valueRange?.min ?? ''"
              class="w-full text-sm rounded-md border border-slate-200 dark:border-slate-600 dark:bg-slate-700 dark:text-slate-200 px-2 py-1"
              @input="onValueMin"
            />
            <span class="text-xs text-slate-400">–</span>
            <input
              type="number"
              :placeholder="t('KANBAN.FILTER.MAX')"
              :value="activeFilters.valueRange?.max ?? ''"
              class="w-full text-sm rounded-md border border-slate-200 dark:border-slate-600 dark:bg-slate-700 dark:text-slate-200 px-2 py-1"
              @input="onValueMax"
            />
          </div>
        </div>

        <!-- Etiquetas -->
        <div class="flex flex-col gap-1">
          <span class="text-xs text-n-slate-11">{{
            t('KANBAN.FILTER.LABEL_LABEL')
          }}</span>
          <div class="relative flex flex-wrap items-center gap-1">
            <button
              class="flex items-center gap-1 px-2 py-0.5 text-xs rounded border border-dashed border-slate-300 dark:border-slate-600 text-slate-500 dark:text-slate-400 hover:bg-slate-50 dark:hover:bg-slate-700 transition-colors"
              @click="toggleLabelPicker"
            >
              <span class="i-lucide-plus size-3" />
              {{ t('KANBAN.FILTER.LABEL_PLACEHOLDER') }}
            </button>
            <woot-label
              v-for="label in selectedLabelObjects"
              :key="label.title"
              :title="label.title"
              :color="label.color"
              show-close
              variant="smooth"
              @remove="onRemoveLabel"
            />
            <div
              v-if="showLabelPicker"
              v-on-click-outside="() => (showLabelPicker = false)"
              class="absolute top-full ltr:left-0 rtl:right-0 mt-1 z-[9999] w-56 border border-n-strong rounded-lg bg-n-alpha-3 backdrop-blur-[100px] shadow-lg p-2"
            >
              <LabelDropdown
                :account-labels="pipelineLabels"
                :selected-labels="selectedLabelTitles"
                :allow-creation="false"
                @add="onAddLabel"
                @remove="onRemoveLabel"
              />
            </div>
          </div>
        </div>

        <!-- Limpar filtros -->
        <button
          class="text-xs text-woot-500 hover:text-woot-600 dark:hover:text-woot-400 hover:underline self-start transition-colors"
          @click="clearFilters"
        >
          {{ t('KANBAN.FILTER.CLEAR') }}
        </button>
      </div>
    </div>
  </div>
</template>
