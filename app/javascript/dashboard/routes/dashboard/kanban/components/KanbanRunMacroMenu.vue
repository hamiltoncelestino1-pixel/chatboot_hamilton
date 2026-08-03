<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import DropdownMenu from 'dashboard/components-next/dropdown-menu/DropdownMenu.vue';

const props = defineProps({
  pipelineItemIds: { type: Array, required: true },
  showLabel: { type: Boolean, default: false },
  buttonClass: { type: String, default: '' },
  openUpward: { type: Boolean, default: false },
});

const { t } = useI18n();
const store = useStore();
const macros = useMapGetter('macros/getMacros');

const showMenu = ref(false);
const executingMacroId = ref(null);

const pipelineMacros = computed(() =>
  macros.value.filter(macro => macro.macro_type === 'pipeline_item')
);

const macroMenuItems = computed(() =>
  pipelineMacros.value.map(macro => ({
    label: macro.name,
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
  if (!props.pipelineItemIds.length || executingMacroId.value) return;

  executingMacroId.value = macro.id;
  try {
    await store.dispatch('macros/execute', {
      macroId: macro.id,
      pipelineItemIds: props.pipelineItemIds,
    });
    // macros/execute only enqueues MacrosPipelineExecutionJob - the cards haven't been
    // mutated yet by the time this resolves. Deliberately not refetching here: a REST
    // fetchItems() fired at this point races the job's own per-card real-time broadcasts
    // (pipeline_item.updated) with a stale snapshot, and SET_ITEMS only adds an item to a
    // stage's order without removing it from a stale one, so the loser of that race gets
    // stuck showing the card in its old column. The board updates via the WebSocket
    // broadcasts alone, same as manual drag-and-drop relies on for other sessions.
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
