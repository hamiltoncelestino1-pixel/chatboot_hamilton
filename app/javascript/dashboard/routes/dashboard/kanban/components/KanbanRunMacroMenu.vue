<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';

const props = defineProps({
  pipelineItemIds: { type: Array, required: true },
  showLabel: { type: Boolean, default: false },
  buttonClass: { type: String, default: '' },
});

const { t } = useI18n();
const store = useStore();
const macros = useMapGetter('macros/getMacros');
const activePipeline = useMapGetter('kanban/getActivePipeline');

const showMenu = ref(false);
const executingMacroId = ref(null);

const pipelineMacros = computed(() =>
  macros.value.filter(macro => macro.macro_type === 'pipeline_item')
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
    // The macro mutates cards server-side (stage/assignee/team/labels/fields) - refetch
    // so the board reflects the change without requiring a manual reload.
    if (activePipeline.value) {
      await store.dispatch('kanban/fetchItems', activePipeline.value.id);
    }
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

    <div
      v-if="showMenu"
      class="absolute right-0 z-[9999] mt-1 w-56 border border-slate-200 dark:border-slate-600 rounded-lg bg-white dark:bg-slate-800 shadow-lg p-1"
      @click.stop
    >
      <p v-if="!pipelineMacros.length" class="px-2 py-2 text-xs text-slate-400">
        {{ t('KANBAN.RUN_MACRO.EMPTY_STATE') }}
      </p>
      <button
        v-for="macro in pipelineMacros"
        :key="macro.id"
        class="flex items-center justify-between w-full px-2 py-1.5 text-sm text-left text-slate-700 dark:text-slate-200 hover:bg-slate-100 dark:hover:bg-slate-700 rounded-md transition-colors disabled:opacity-50"
        :disabled="!!executingMacroId"
        @click="runMacro(macro)"
      >
        <span class="truncate">{{ macro.name }}</span>
        <span
          v-if="executingMacroId === macro.id"
          class="i-lucide-loader size-3.5 animate-spin flex-shrink-0"
        />
        <span v-else class="i-lucide-play size-3.5 flex-shrink-0" />
      </button>
    </div>
  </div>
</template>
