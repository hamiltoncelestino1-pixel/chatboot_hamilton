<script>
import SingleSelect from 'dashboard/components-next/filter/inputs/SingleSelect.vue';

export default {
  components: {
    SingleSelect,
  },
  props: {
    modelValue: { type: [Object, Array], default: () => ({}) },
    actionName: { type: String, required: true },
    dropdownMaxHeight: { type: String, default: 'max-h-80' },
  },
  emits: ['update:modelValue'],
  data() {
    return {
      pipelineId: null,
      targetPipelineId: null,
      targetStageId: null,
    };
  },
  computed: {
    isExport() {
      return this.actionName === 'export_pipeline_item';
    },
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
        if (!this.isExport) {
          this.targetStageId = null;
        }
        this.updateValue();
      },
    },
    targetPipelineOptions() {
      return this.pipelineOptions;
    },
    selectedTargetPipeline: {
      get() {
        return (
          this.targetPipelineOptions.find(
            p => p.id === this.targetPipelineId
          ) || null
        );
      },
      set(option) {
        this.targetPipelineId = option?.id || null;
        this.targetStageId = null;
        this.updateValue();
      },
    },
    stageSourcePipelineId() {
      return this.isExport ? this.targetPipelineId : this.pipelineId;
    },
    stageOptions() {
      if (!this.stageSourcePipelineId) return [];
      return this.$store.getters['kanban/getStagesForPipeline'](
        this.stageSourcePipelineId
      ).map(stage => ({ id: stage.id, name: stage.name }));
    },
    selectedStage: {
      get() {
        return this.stageOptions.find(s => s.id === this.targetStageId) || null;
      },
      set(option) {
        this.targetStageId = option?.id || null;
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
    this.targetPipelineId = data.target_pipeline_id
      ? Number(data.target_pipeline_id)
      : null;
    this.targetStageId = data.target_stage_id
      ? Number(data.target_stage_id)
      : null;

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
      const payload = { pipeline_id: this.pipelineId };
      if (this.isExport) {
        payload.target_pipeline_id = this.targetPipelineId;
        payload.target_stage_id = this.targetStageId;
      } else {
        payload.target_stage_id = this.targetStageId;
      }
      this.$emit('update:modelValue', payload);
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
