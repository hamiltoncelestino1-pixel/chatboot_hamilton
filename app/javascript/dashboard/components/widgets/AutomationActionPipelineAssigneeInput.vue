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
      assigneeMode: 'none',
      teamMode: 'none',
    };
  },
  computed: {
    isTeam() {
      return this.actionName === 'assign_pipeline_item_team';
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
    this.assigneeMode = data.assignee_mode || 'none';
    this.teamMode = data.team_mode || 'none';

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
      if (this.isTeam) {
        payload.team_mode = this.teamMode;
      } else {
        payload.assignee_mode = this.assigneeMode;
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
    <SingleSelect
      v-if="isTeam"
      v-model="selectedTeamMode"
      :options="teamModeOptions"
      :placeholder="$t('AUTOMATION.ACTION.PIPELINE.TEAM_MODE_PLACEHOLDER')"
      :dropdown-max-height="dropdownMaxHeight"
    />
    <SingleSelect
      v-else
      v-model="selectedAssigneeMode"
      :options="assigneeModeOptions"
      :placeholder="$t('AUTOMATION.ACTION.PIPELINE.ASSIGNEE_MODE_PLACEHOLDER')"
      :dropdown-max-height="dropdownMaxHeight"
    />
  </div>
</template>
