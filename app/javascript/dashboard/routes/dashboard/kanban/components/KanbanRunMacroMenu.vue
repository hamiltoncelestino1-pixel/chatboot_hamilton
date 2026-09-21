<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import DropdownMenu from 'dashboard/components-next/dropdown-menu/DropdownMenu.vue';

// Two mutually exclusive scopes (task 07): an explicit list of ids (single card, from
// KanbanCard.vue) or a stageId (+ itemCount just to label it - the actual set is resolved
// server-side from the board's active filters, not from this list) to run on the whole column.
const props = defineProps({
  pipelineItemIds: { type: Array, default: null },
  stageId: { type: Number, default: null },
  itemCount: { type: Number, default: 0 },
  showLabel: { type: Boolean, default: false },
  buttonClass: { type: String, default: '' },
  openUpward: { type: Boolean, default: false },
});

const { t } = useI18n();
const store = useStore();
const macros = useMapGetter('macros/getMacros');
const activeFilterParams = useMapGetter('kanban/getActiveFilterParams');

const showMenu = ref(false);
const executingMacroId = ref(null);

const isColumnScope = computed(() => props.stageId != null);
const scopeCount = computed(() =>
  isColumnScope.value ? props.itemCount : props.pipelineItemIds?.length || 0
);

const pipelineMacros = computed(() =>
  macros.value.filter(macro => macro.macro_type === 'pipeline_item')
);

// The count is shown right on the option so the agent sees the real scope before clicking -
// same number as the column badge, never "however many happen to be loaded" (task 07's whole
// point: that number used to be silently wrong under pagination).
const macroMenuItems = computed(() =>
  pipelineMacros.value.map(macro => ({
    label: isColumnScope.value
      ? t('KANBAN.RUN_MACRO.COLUMN_ITEM_LABEL', {
          name: macro.name,
          count: scopeCount.value,
        })
      : macro.name,
    action: 'run',
    value: macro.id,
    macro,
    icon:
      executingMacroId.value === macro.id
        ? 'i-lucide-loader animate-spin'
        : 'i-lucide-play',
    disabled: !!executingMacroId.value,
  }))
);

onMounted(() => {
  if (!macros.value.length) {
    store.dispatch('macros/get');
  }
});

const toggleMenu = () => {
  showMenu.value = !showMenu.value;
};

const closeMenu = () => {
  showMenu.value = false;
};

const runMacro = async macro => {
  if (!scopeCount.value || executingMacroId.value) return;

  executingMacroId.value = macro.id;
  try {
    await store.dispatch('macros/execute', {
      macroId: macro.id,
      pipelineItemIds: isColumnScope.value ? null : props.pipelineItemIds,
      stageId: isColumnScope.value ? props.stageId : null,
      filters: isColumnScope.value ? activeFilterParams.value : undefined,
    });
    // macros/execute only enqueues MacrosPipelineExecutionJob - the cards haven't been
    // mutated yet by the time this resolves. Deliberately not refetching here: a REST
    // refetch fired at this point races the job's own per-card real-time broadcasts
    // (pipeline_item.updated, handled by applyRealtimePipelineItem) with a stale snapshot,
    // and the loser of that race would overwrite the other with outdated data. The board
    // updates via the WebSocket broadcasts alone, same as manual drag-and-drop relies on for
    // other sessions.
    useAlert(t('KANBAN.RUN_MACRO.SUCCESS'));
  } catch (error) {
    useAlert(t('KANBAN.RUN_MACRO.ERROR'));
  } finally {
    executingMacroId.value = null;
    showMenu.value = false;
  }
};
</script>

<template>
  <div v-on-clickaway="closeMenu" class="relative inline-block">
    <button
      v-tooltip="!showLabel ? t('KANBAN.RUN_MACRO.BUTTON') : undefined"
      :class="buttonClass"
      @click.stop="toggleMenu"
    >
      <span
        class="i-lucide-zap flex-shrink-0"
        :class="showLabel ? 'size-4' : 'size-3.5'"
      />
      <span v-if="showLabel">{{ t('KANBAN.RUN_MACRO.BUTTON') }}</span>
    </button>

    <DropdownMenu
      v-if="showMenu"
      :menu-sections="[
        {
          items: macroMenuItems,
          emptyState: t('KANBAN.RUN_MACRO.EMPTY_STATE'),
        },
      ]"
      :class="
        openUpward
          ? 'mb-1 ltr:right-0 rtl:left-0 bottom-full'
          : 'mt-1 ltr:right-0 rtl:left-0 top-full'
      "
      @action="({ macro }) => runMacro(macro)"
    />
  </div>
</template>
