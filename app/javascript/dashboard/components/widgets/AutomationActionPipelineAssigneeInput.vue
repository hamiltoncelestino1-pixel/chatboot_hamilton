<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import { usePipelineSelector } from 'dashboard/composables/usePipelineSelector';
import SingleSelect from 'dashboard/components-next/filter/inputs/SingleSelect.vue';

const props = defineProps({
  modelValue: { type: [Object, Array], default: () => ({}) },
  actionName: { type: String, required: true },
  dropdownMaxHeight: { type: String, default: 'max-h-80' },
});
const emit = defineEmits(['update:modelValue']);

const { t } = useI18n();

const isTeam = computed(() => props.actionName === 'assign_pipeline_item_team');

const assigneeMode = ref('none');
const teamMode = ref('none');

const { pipelineId, pipelineOptions, defaultToFirstPipeline, onAutoSelect } =
  usePipelineSelector();

const updateValue = () => {
  const payload = { pipeline_id: pipelineId.value };
  if (isTeam.value) {
    payload.team_mode = teamMode.value;
  } else {
    payload.assignee_mode = assigneeMode.value;
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
    updateValue();
  },
});

const agents = useMapGetter('agents/getVerifiedAgents');
const teams = useMapGetter('teams/getTeams');

const assigneeModeOptions = computed(() => [
  {
    id: 'conversation_assignee',
    name: t('AUTOMATION.ACTION.PIPELINE.ASSIGNEE_MODE.CONVERSATION_ASSIGNEE'),
  },
  { id: 'none', name: t('AUTOMATION.ACTION.PIPELINE.ASSIGNEE_MODE.NONE') },
  ...agents.value.map(agent => ({ id: String(agent.id), name: agent.name })),
]);

const selectedAssigneeMode = computed({
  get: () =>
    assigneeModeOptions.value.find(
      option => option.id === assigneeMode.value
    ) || null,
  set: option => {
    assigneeMode.value = option?.id || 'none';
    updateValue();
  },
});

const teamModeOptions = computed(() => [
  {
    id: 'conversation_team',
    name: t('AUTOMATION.ACTION.PIPELINE.TEAM_MODE.CONVERSATION_TEAM'),
  },
  { id: 'none', name: t('AUTOMATION.ACTION.PIPELINE.TEAM_MODE.NONE') },
  ...teams.value.map(team => ({ id: String(team.id), name: team.name })),
]);

const selectedTeamMode = computed({
  get: () =>
    teamModeOptions.value.find(option => option.id === teamMode.value) || null,
  set: option => {
    teamMode.value = option?.id || 'none';
    updateValue();
  },
});

onMounted(() => {
  const data = Array.isArray(props.modelValue) ? {} : props.modelValue || {};
  pipelineId.value = data.pipeline_id ? Number(data.pipeline_id) : null;
  assigneeMode.value = data.assignee_mode || 'none';
  teamMode.value = data.team_mode || 'none';

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
