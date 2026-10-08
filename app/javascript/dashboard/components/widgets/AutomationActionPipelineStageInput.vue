<script setup>
import { computed, onMounted, ref } from 'vue';
import { useFunctionGetter } from 'dashboard/composables/store';
import { usePipelineSelector } from 'dashboard/composables/usePipelineSelector';
import { usePipelineLostReasonsStore } from 'dashboard/stores/pipelineLostReasons';
import SingleSelect from 'dashboard/components-next/filter/inputs/SingleSelect.vue';

const props = defineProps({
  modelValue: { type: [Object, Array], default: () => ({}) },
  actionName: { type: String, required: true },
  dropdownMaxHeight: { type: String, default: 'max-h-80' },
});
const emit = defineEmits(['update:modelValue']);

const isExport = computed(() => props.actionName === 'export_pipeline_item');
const isMoveStage = computed(
  () => props.actionName === 'move_pipeline_item_stage'
);

const targetPipelineId = ref(null);
const targetStageId = ref(null);
const lostReasonId = ref(null);

const { pipelineId, pipelineOptions, defaultToFirstPipeline, onAutoSelect } =
  usePipelineSelector();

const stageSourcePipelineId = computed(() =>
  isExport.value ? targetPipelineId.value : pipelineId.value
);
const stagesForSource = useFunctionGetter(
  'kanban/getStagesForPipeline',
  stageSourcePipelineId
);
const stageOptions = computed(() => {
  if (!stageSourcePipelineId.value) return [];
  return stagesForSource.value.map(stage => ({
    id: stage.id,
    name: stage.name,
  }));
});

// Only 'move_pipeline_item_stage' collects a fixed lost reason here - the manual
// drag-and-drop/card-panel flow already prompts per-card via LostReasonModal.vue, and
// 'export_pipeline_item' moving into a lost stage of another pipeline is a separate,
// not-yet-covered case (claude/crm_features_fixes_tasks/01, out of scope).
const targetStageIsLost = computed(() => {
  if (!isMoveStage.value || !targetStageId.value) return false;
  const stage = stagesForSource.value.find(s => s.id === targetStageId.value);
  return stage?.stage_type === 'lost';
});

const updateValue = () => {
  const payload = { pipeline_id: pipelineId.value };
  if (isExport.value) {
    payload.target_pipeline_id = targetPipelineId.value;
    payload.target_stage_id = targetStageId.value;
  } else {
    payload.target_stage_id = targetStageId.value;
  }
  if (targetStageIsLost.value && lostReasonId.value) {
    payload.pipeline_lost_reason_id = lostReasonId.value;
  }
  emit('update:modelValue', payload);
};
onAutoSelect(updateValue);

const lostReasonsStore = usePipelineLostReasonsStore();
const lostReasonOptions = computed(() =>
  lostReasonsStore.getRecords.map(reason => ({
    id: reason.id,
    name: reason.title,
  }))
);
const selectedLostReason = computed({
  get: () =>
    lostReasonOptions.value.find(option => option.id === lostReasonId.value) ||
    null,
  set: option => {
    lostReasonId.value = option?.id || null;
    updateValue();
  },
});

const selectedPipeline = computed({
  get: () =>
    pipelineOptions.value.find(option => option.id === pipelineId.value) ||
    null,
  set: option => {
    pipelineId.value = option?.id || null;
    if (!isExport.value) {
      targetStageId.value = null;
    }
    updateValue();
  },
});

// export_pipeline_item's target pipeline is a plain manual picker - unlike the source
// pipeline, it has no autoselect-first-pipeline behavior, so it doesn't go through
// usePipelineSelector; it just reuses the same pipelineOptions list.
const targetPipelineOptions = computed(() => pipelineOptions.value);
const selectedTargetPipeline = computed({
  get: () =>
    targetPipelineOptions.value.find(
      option => option.id === targetPipelineId.value
    ) || null,
  set: option => {
    targetPipelineId.value = option?.id || null;
    targetStageId.value = null;
    updateValue();
  },
});

const selectedStage = computed({
  get: () =>
    stageOptions.value.find(option => option.id === targetStageId.value) ||
    null,
  set: option => {
    targetStageId.value = option?.id || null;
    lostReasonId.value = null;
    updateValue();
  },
});

onMounted(() => {
  const data = Array.isArray(props.modelValue) ? {} : props.modelValue || {};
  pipelineId.value = data.pipeline_id ? Number(data.pipeline_id) : null;
  targetPipelineId.value = data.target_pipeline_id
    ? Number(data.target_pipeline_id)
    : null;
  targetStageId.value = data.target_stage_id
    ? Number(data.target_stage_id)
    : null;
  lostReasonId.value = data.pipeline_lost_reason_id
    ? Number(data.pipeline_lost_reason_id)
    : null;

  if (!pipelineId.value) {
    defaultToFirstPipeline();
  }
  if (isMoveStage.value && !lostReasonsStore.getRecords.length) {
    lostReasonsStore.get();
  }
});
</script>

<template>
  <div class="flex items-center gap-2">
    <SingleSelect
      v-model="selectedPipeline"
      :options="pipelineOptions"
      :placeholder="$t('AUTOMATION.ACTION.PIPELINE.PIPELINE_PLACEHOLDER')"
      :dropdown-max-height="dropdownMaxHeight"
    />
    <template v-if="isExport">
      <SingleSelect
        v-model="selectedTargetPipeline"
        :options="targetPipelineOptions"
        :placeholder="
          $t('AUTOMATION.ACTION.PIPELINE.TARGET_PIPELINE_PLACEHOLDER')
        "
        :dropdown-max-height="dropdownMaxHeight"
      />
    </template>
    <SingleSelect
      v-model="selectedStage"
      :options="stageOptions"
      :placeholder="$t('AUTOMATION.ACTION.PIPELINE.STAGE_PLACEHOLDER')"
      :dropdown-max-height="dropdownMaxHeight"
    />
    <SingleSelect
      v-if="targetStageIsLost"
      v-model="selectedLostReason"
      :options="lostReasonOptions"
      :placeholder="$t('AUTOMATION.ACTION.PIPELINE.LOST_REASON_PLACEHOLDER')"
      :dropdown-max-height="dropdownMaxHeight"
    />
  </div>
</template>
