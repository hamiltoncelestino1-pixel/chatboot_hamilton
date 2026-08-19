<script setup>
import { ref, onMounted } from 'vue';
import NextInput from 'dashboard/components-next/input/Input.vue';

const props = defineProps({
  modelValue: { type: [Object, Array], default: () => ({}) },
});
const emit = defineEmits(['update:modelValue']);

const title = ref('');
const dueInDays = ref('');

const updateValue = () => {
  emit('update:modelValue', {
    title: title.value || null,
    due_in_days: dueInDays.value || null,
  });
};

onMounted(() => {
  const data = Array.isArray(props.modelValue) ? {} : props.modelValue || {};
  title.value = data.title || '';
  dueInDays.value = data.due_in_days || '';
});
</script>

<template>
  <div class="flex flex-col gap-2">
    <NextInput
      v-model="title"
      type="text"
      size="sm"
      :placeholder="$t('AUTOMATION.ACTION.PIPELINE.TASK_TITLE_PLACEHOLDER')"
      @update:model-value="updateValue"
    />
    <NextInput
      v-model="dueInDays"
      type="number"
      size="sm"
      min="0"
      :placeholder="
        $t('AUTOMATION.ACTION.PIPELINE.TASK_DUE_IN_DAYS_PLACEHOLDER')
      "
      @update:model-value="updateValue"
    />
  </div>
</template>
