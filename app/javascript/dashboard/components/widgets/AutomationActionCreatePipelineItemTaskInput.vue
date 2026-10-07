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
    // 0 means "due today" and is a value the field accepts, so emptiness has to be tested as
    // emptiness - `|| null` would turn a typed 0 into null on the way out and `|| ''` would
    // blank the field on the way back in. Input.vue already gives us a real Number here
    // (it coerces non-empty values when type is number), so this is '' or a number.
    due_in_days: dueInDays.value === '' ? null : dueInDays.value,
  });
};

onMounted(() => {
  const data = Array.isArray(props.modelValue) ? {} : props.modelValue || {};
  title.value = data.title || '';
  dueInDays.value = data.due_in_days ?? '';
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
