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
      pipelineStageId: null,
      assigneeMode: 'none',
      teamMode: 'none',
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
        this.pipelineStageId = null;
        this.updateValue();
      },
    },
    stageOptions() {
      if (!this.pipelineId) return [];
      return this.$store.getters['kanban/getStagesForPipeline'](
        this.pipelineId
      ).map(stage => ({ id: stage.id, name: stage.name }));
    },
    selectedStage: {
      get() {
        return (
          this.stageOptions.find(s => s.id === this.pipelineStageId) || null
        );
      },
      set(option) {
        this.pipelineStageId = option?.id || null;
        this.updateValue();
      },
    },
    agents() {
      return this.$store.getters['agents/getVerifiedAgents'];
    },
    teams() {
      return this.$store.getters['teams/getTeams'];
    },
    assigneeModeOptions() {
      return [
        {
          id: 'conversation_assignee',
          name: this.$t(
            'AUTOMATION.ACTION.PIPELINE.ASSIGNEE_MODE.CONVERSATION_ASSIGNEE'
          ),
        },
        {
          id: 'none',
          name: this.$t('AUTOMATION.ACTION.PIPELINE.ASSIGNEE_MODE.NONE'),
        },
        ...this.agents.map(agent => ({
          id: String(agent.id),
          name: agent.name,
        })),
      ];
    },
    selectedAssigneeMode: {
      get() {
        return (
          this.assigneeModeOptions.find(o => o.id === this.assigneeMode) || null
        );
      },
      set(option) {
        this.assigneeMode = option?.id || 'none';
        this.updateValue();
      },
    },
    teamModeOptions() {
      return [
        {
          id: 'conversation_team',
          name: this.$t(
            'AUTOMATION.ACTION.PIPELINE.TEAM_MODE.CONVERSATION_TEAM'
          ),
        },
        {
          id: 'none',
          name: this.$t('AUTOMATION.ACTION.PIPELINE.TEAM_MODE.NONE'),
        },
        ...this.teams.map(team => ({ id: String(team.id), name: team.name })),
      ];
    },
    selectedTeamMode: {
      get() {
        return this.teamModeOptions.find(o => o.id === this.teamMode) || null;
      },
      set(option) {
        this.teamMode = option?.id || 'none';
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
    this.pipelineStageId = data.pipeline_stage_id
      ? Number(data.pipeline_stage_id)
      : null;
    this.assigneeMode = data.assignee_mode || 'none';
    this.teamMode = data.team_mode || 'none';
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
      const [firstStage] = this.$store.getters['kanban/getStagesForPipeline'](
        this.pipelineId
      );
      this.pipelineStageId = firstStage?.id || null;
      this.updateValue();
    },
    updateValue() {
      this.$emit('update:modelValue', {
        pipeline_id: this.pipelineId,
        pipeline_stage_id: this.pipelineStageId,
        assignee_mode: this.assigneeMode,
        team_mode: this.teamMode,
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
    <div class="flex items-center gap-2">
      <SingleSelect
        v-model="selectedPipeline"
        :options="pipelineOptions"
        :placeholder="$t('AUTOMATION.ACTION.PIPELINE.PIPELINE_PLACEHOLDER')"
        :dropdown-max-height="dropdownMaxHeight"
      />
      <SingleSelect
        v-model="selectedStage"
        :options="stageOptions"
        :placeholder="$t('AUTOMATION.ACTION.PIPELINE.STAGE_PLACEHOLDER')"
        :dropdown-max-height="dropdownMaxHeight"
      />
    </div>
    <div class="flex items-center gap-2">
      <SingleSelect
        v-model="selectedAssigneeMode"
        :options="assigneeModeOptions"
        :placeholder="
          $t('AUTOMATION.ACTION.PIPELINE.ASSIGNEE_MODE_PLACEHOLDER')
        "
        :dropdown-max-height="dropdownMaxHeight"
      />
      <SingleSelect
        v-model="selectedTeamMode"
        :options="teamModeOptions"
        :placeholder="$t('AUTOMATION.ACTION.PIPELINE.TEAM_MODE_PLACEHOLDER')"
        :dropdown-max-height="dropdownMaxHeight"
      />
    </div>
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
