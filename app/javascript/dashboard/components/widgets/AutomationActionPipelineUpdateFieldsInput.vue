<script>
import SingleSelect from 'dashboard/components-next/filter/inputs/SingleSelect.vue';
import NextInput from 'dashboard/components-next/input/Input.vue';

export default {
  components: {
    SingleSelect,
    NextInput,
  },
  props: {
    modelValue: { type: [Object, Array], default: () => ({}) },
    dropdownMaxHeight: { type: String, default: 'max-h-80' },
  },
  emits: ['update:modelValue'],
  data() {
    return {
      pipelineId: null,
      title: '',
      value: '',
      notes: '',
    };
  },
  computed: {
    pipelines() {
      return this.$store.getters['kanban/getPipelines'];
    },
    pipelineOptions() {
      return this.pipelines.map(pipeline => ({
        id: pipeline.id,
        name: pipeline.name,
      }));
    },
    selectedPipeline: {
      get() {
        return this.pipelineOptions.find(p => p.id === this.pipelineId) || null;
      },
      set(option) {
        this.pipelineId = option?.id || null;
        this.updateValue();
      },
    },
  },
  watch: {
    pipelines(list) {
      if (!this.pipelineId && list.length) {
        this.defaultToFirstPipeline();
      }
    },
  },
  mounted() {
    if (!this.pipelines.length) {
      this.$store.dispatch('kanban/fetchPipelines');
    }
    const data = Array.isArray(this.modelValue) ? {} : this.modelValue || {};
    this.pipelineId = data.pipeline_id ? Number(data.pipeline_id) : null;
    this.title = data.title || '';
    this.value = data.value || '';
    this.notes = data.notes || '';

    if (!this.pipelineId) {
      this.defaultToFirstPipeline();
    }
  },
  methods: {
    defaultToFirstPipeline() {
      if (!this.pipelines.length) return;
      this.pipelineId = this.pipelines[0].id;
      this.updateValue();
    },
    updateValue() {
      this.$emit('update:modelValue', {
        pipeline_id: this.pipelineId,
        title: this.title || null,
        value: this.value || null,
        notes: this.notes || null,
      });
    },
  },
};
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
