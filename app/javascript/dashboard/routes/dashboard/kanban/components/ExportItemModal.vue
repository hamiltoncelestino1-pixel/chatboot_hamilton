<script setup>
import { ref, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';

const props = defineProps({ item: { type: Object, required: true } });
const emit = defineEmits(['close']);

const { t } = useI18n();
const store = useStore();
const pipelines = useMapGetter('kanban/getPipelines');
const getStagesForPipeline = useMapGetter('kanban/getStagesForPipeline');
const getPipelineMembers = useMapGetter('pipelineMembers/getPipelineMembers');
const uiFlags = useMapGetter('kanban/getUIFlags');

const availablePipelines = computed(() =>
  pipelines.value.filter(p => p.id !== props.item.pipeline_id)
);

const targetPipelineId = ref(null);
const targetStageId = ref(null);

const targetStages = computed(() =>
  targetPipelineId.value
    ? getStagesForPipeline.value(targetPipelineId.value)
    : []
);

watch(targetPipelineId, pipelineId => {
  targetStageId.value = null;
  if (pipelineId) {
    store.dispatch('pipelineMembers/get', { pipelineId });
  }
});

const willLoseAssignee = computed(() => {
  if (!props.item.assignee || !targetPipelineId.value) return false;
  const members = getPipelineMembers.value(targetPipelineId.value);
  return !members.some(m => m.id === props.item.assignee.id);
});

const canSubmit = computed(() => targetPipelineId.value && targetStageId.value);

const handleExport = async () => {
  try {
    await store.dispatch('kanban/exportItem', {
      itemId: props.item.id,
      targetPipelineId: targetPipelineId.value,
      targetStageId: targetStageId.value,
    });
    useAlert(t('KANBAN.ITEM.EXPORT.SUCCESS'));
    emit('close');
  } catch (error) {
    useAlert(error?.response?.data?.error || t('KANBAN.ITEM.EXPORT.ERROR'));
  }
};
</script>

<template>
  <Teleport to="body">
    <div
      class="fixed inset-0 z-50 flex items-center justify-center"
      @click.self="emit('close')"
    >
      <div class="fixed inset-0 bg-black/30" @click="emit('close')" />

      <div
        class="relative w-full max-w-sm bg-white dark:bg-slate-800 rounded-xl shadow-xl z-10 p-5"
      >
        <div class="flex items-center justify-between mb-4">
          <h3
            class="text-base font-semibold text-slate-800 dark:text-slate-100"
          >
            {{ t('KANBAN.ITEM.EXPORT.TITLE') }}
          </h3>
          <button
            class="text-slate-400 hover:text-slate-600 dark:hover:text-slate-200 transition-colors"
            @click="emit('close')"
          >
            <span class="i-lucide-x size-5" />
          </button>
        </div>

        <div class="space-y-3">
          <div>
            <label
              class="block text-xs font-medium text-slate-600 dark:text-slate-400 mb-1"
            >
              {{ t('KANBAN.ITEM.EXPORT.TARGET_PIPELINE_LABEL') }}
            </label>
            <select
              v-model="targetPipelineId"
              class="w-full px-3 py-2 text-sm border border-slate-200 dark:border-slate-600 rounded-lg bg-white dark:bg-slate-700 text-slate-800 dark:text-slate-100 focus:outline-none focus:ring-2 focus:ring-woot-500"
            >
              <option value="" disabled selected>—</option>
              <option
                v-for="pipeline in availablePipelines"
                :key="pipeline.id"
                :value="pipeline.id"
              >
                {{ pipeline.name }}
              </option>
            </select>
          </div>

          <div>
            <label
              class="block text-xs font-medium text-slate-600 dark:text-slate-400 mb-1"
            >
              {{ t('KANBAN.ITEM.EXPORT.TARGET_STAGE_LABEL') }}
            </label>
            <select
              v-model="targetStageId"
              :disabled="!targetPipelineId"
              class="w-full px-3 py-2 text-sm border border-slate-200 dark:border-slate-600 rounded-lg bg-white dark:bg-slate-700 text-slate-800 dark:text-slate-100 focus:outline-none focus:ring-2 focus:ring-woot-500 disabled:opacity-50"
            >
              <option value="" disabled selected>—</option>
              <option
                v-for="stage in targetStages"
                :key="stage.id"
                :value="stage.id"
              >
                {{ stage.name }}
              </option>
            </select>
          </div>

          <div
            v-if="willLoseAssignee"
            class="flex items-start gap-2 p-3 bg-amber-50 dark:bg-amber-900/20 rounded-lg text-xs text-amber-700 dark:text-amber-400"
          >
            <span class="i-lucide-triangle-alert size-4 flex-shrink-0 mt-0.5" />
            <span>{{ t('KANBAN.ITEM.EXPORT.ASSIGNEE_STRIPPED_NOTICE') }}</span>
          </div>
        </div>

        <div class="flex justify-end gap-2 mt-5">
          <button
            class="px-4 py-2 text-sm text-slate-600 dark:text-slate-400 hover:bg-slate-100 dark:hover:bg-slate-700 rounded-lg transition-colors"
            @click="emit('close')"
          >
            {{ t('KANBAN.ITEM.EXPORT.CANCEL') }}
          </button>
          <button
            class="px-4 py-2 text-sm font-medium text-white bg-woot-500 hover:bg-woot-600 rounded-lg transition-colors disabled:opacity-50"
            :disabled="!canSubmit || uiFlags.isExporting"
            @click="handleExport"
          >
            {{ t('KANBAN.ITEM.EXPORT.SUBMIT') }}
          </button>
        </div>
      </div>
    </div>
  </Teleport>
</template>
