<script>
import SingleSelect from 'dashboard/components-next/filter/inputs/SingleSelect.vue';
import MultiSelect from 'dashboard/components-next/filter/inputs/MultiSelect.vue';

export default {
  components: {
    SingleSelect,
    MultiSelect,
  },
  props: {
    modelValue: { type: [Object, Array], default: () => ({}) },
    dropdownMaxHeight: { type: String, default: 'max-h-80' },
  },
  emits: ['update:modelValue'],
  data() {
    return {
      pipelineId: null,
      selectedLabels: [],
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
    pipelineLabels() {
      return this.$store.getters['labels/getPipelineLabels'];
    },
    labelOptions() {
      return this.pipelineLabels.map(label => ({
        id: label.title,
        name: label.title,
      }));
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
    this.selectedLabels = (data.labels || []).map(title => ({
      id: title,
      name: title,
    }));

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
        labels: this.selectedLabels.map(label => label.id),
      });
    },
  },
};
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
