<script setup>
import { computed, onMounted, ref } from 'vue';
import { usePipelineSelector } from 'dashboard/composables/usePipelineSelector';
import SingleSelect from 'dashboard/components-next/filter/inputs/SingleSelect.vue';
import NextInput from 'dashboard/components-next/input/Input.vue';

const props = defineProps({
  modelValue: { type: [Object, Array], default: () => ({}) },
  dropdownMaxHeight: { type: String, default: 'max-h-80' },
});
const emit = defineEmits(['update:modelValue']);

const title = ref('');
const value = ref('');
const notes = ref('');

const { pipelineId, pipelineOptions, defaultToFirstPipeline, onAutoSelect } =
  usePipelineSelector();

const updateValue = () => {
  emit('update:modelValue', {
    pipeline_id: pipelineId.value,
    title: title.value || null,
    value: value.value || null,
    notes: notes.value || null,
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

onMounted(() => {
  const data = Array.isArray(props.modelValue) ? {} : props.modelValue || {};
  pipelineId.value = data.pipeline_id ? Number(data.pipeline_id) : null;
  title.value = data.title || '';
  value.value = data.value || '';
  notes.value = data.notes || '';

  if (!pipelineId.value) {
    defaultToFirstPipeline();
  }
});
</script>

<template>
  <div class="flex flex-col gap-2">
    <SingleSelect
      v-model="selectedPipeline"
      :options="pipelineOptions"
      :placeholder="$t('AUTOMATION.ACTION.PIPELINE.PIPELINE_PLACEHOLDER')"
      :dropdown-max-height="dropdownMaxHeight"
    />
    <NextInput
      v-model="title"
      type="text"
      size="sm"
      :placeholder="$t('AUTOMATION.ACTION.PIPELINE.TITLE_PLACEHOLDER')"
      @update:model-value="updateValue"
    />
    <NextInput
      v-model="value"
      type="number"
      size="sm"
      :placeholder="$t('AUTOMATION.ACTION.PIPELINE.VALUE_PLACEHOLDER')"
      @update:model-value="updateValue"
    />
    <textarea
      v-model="notes"
      class="mb-0 !text-sm"
      rows="2"
      :placeholder="$t('AUTOMATION.ACTION.PIPELINE.NOTES_PLACEHOLDER')"
      @input="updateValue"
    />
  </div>
</template>
