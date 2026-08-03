<script setup>
import { computed, onMounted, ref } from 'vue';
import { useFunctionGetter } from 'dashboard/composables/store';
import { usePipelineSelector } from 'dashboard/composables/usePipelineSelector';
import SingleSelect from 'dashboard/components-next/filter/inputs/SingleSelect.vue';

const props = defineProps({
  modelValue: { type: [Object, Array], default: () => ({}) },
  actionName: { type: String, required: true },
  dropdownMaxHeight: { type: String, default: 'max-h-80' },
});
const emit = defineEmits(['update:modelValue']);

const isExport = computed(() => props.actionName === 'export_pipeline_item');

const targetPipelineId = ref(null);
const targetStageId = ref(null);

const { pipelineId, pipelineOptions, defaultToFirstPipeline, onAutoSelect } =
  usePipelineSelector();

const updateValue = () => {
  const payload = { pipeline_id: pipelineId.value };
  if (isExport.value) {
    payload.target_pipeline_id = targetPipelineId.value;
    payload.target_stage_id = targetStageId.value;
  } else {
    payload.target_stage_id = targetStageId.value;
  }
  emit('update:modelValue', payload);
};
onAutoSelect(updateValue);

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
const selectedStage = computed({
  get: () =>
    stageOptions.value.find(option => option.id === targetStageId.value) ||
    null,
  set: option => {
    targetStageId.value = option?.id || null;
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

  if (!pipelineId.value) {
    defaultToFirstPipeline();
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
  </div>
</template>
