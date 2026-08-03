<script setup>
import { computed, onMounted, ref } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import { usePipelineSelector } from 'dashboard/composables/usePipelineSelector';
import SingleSelect from 'dashboard/components-next/filter/inputs/SingleSelect.vue';
import MultiSelect from 'dashboard/components-next/filter/inputs/MultiSelect.vue';

const props = defineProps({
  modelValue: { type: [Object, Array], default: () => ({}) },
  dropdownMaxHeight: { type: String, default: 'max-h-80' },
});
const emit = defineEmits(['update:modelValue']);

const selectedLabels = ref([]);

const { pipelineId, pipelineOptions, defaultToFirstPipeline, onAutoSelect } =
  usePipelineSelector();

const updateValue = () => {
  emit('update:modelValue', {
    pipeline_id: pipelineId.value,
    labels: selectedLabels.value.map(label => label.id),
  });
};
onAutoSelect(updateValue);

const selectedPipeline = computed({
  get: () =>
    pipelineOptions.value.find(option => option.id === pipelineId.value) ||
    null,
  set: option => {
    pipelineId.value = option?.id || null;
    updateValue();
  },
});

const pipelineLabels = useMapGetter('labels/getPipelineLabels');
const labelOptions = computed(() =>
  pipelineLabels.value.map(label => ({ id: label.title, name: label.title }))
);

onMounted(() => {
  const data = Array.isArray(props.modelValue) ? {} : props.modelValue || {};
  pipelineId.value = data.pipeline_id ? Number(data.pipeline_id) : null;
  selectedLabels.value = (data.labels || []).map(title => ({
    id: title,
    name: title,
  }));

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
    <MultiSelect
      v-model="selectedLabels"
      :options="labelOptions"
      :dropdown-max-height="dropdownMaxHeight"
      @update:model-value="updateValue"
    />
  </div>
</template>
