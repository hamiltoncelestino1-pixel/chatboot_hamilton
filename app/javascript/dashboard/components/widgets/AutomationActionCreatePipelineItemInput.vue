<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import {
  useMapGetter,
  useFunctionGetter,
  useStore,
} from 'dashboard/composables/store';
import { usePipelineSelector } from 'dashboard/composables/usePipelineSelector';
import SingleSelect from 'dashboard/components-next/filter/inputs/SingleSelect.vue';
import NextInput from 'dashboard/components-next/input/Input.vue';

const props = defineProps({
  modelValue: { type: [Object, Array], default: () => ({}) },
  dropdownMaxHeight: { type: String, default: 'max-h-80' },
});
const emit = defineEmits(['update:modelValue']);

const { t } = useI18n();
const store = useStore();

const pipelineStageId = ref(null);
const assigneeMode = ref('none');
const teamMode = ref('none');
const title = ref('');
const value = ref('');
const notes = ref('');

const { pipelineId, pipelineOptions, defaultToFirstPipeline, onAutoSelect } =
  usePipelineSelector();

const updateValue = () => {
  emit('update:modelValue', {
    pipeline_id: pipelineId.value,
    pipeline_stage_id: pipelineStageId.value,
    assignee_mode: assigneeMode.value,
    team_mode: teamMode.value,
    title: title.value || null,
    // Same reasoning as due_in_days in AutomationActionCreatePipelineItemTaskInput: a card
    // worth 0 is a real value, and `|| null` would silently discard it.
    value: value.value === '' ? null : value.value,
    notes: notes.value || null,
  });
};

// On autoselect (mount or once the pipeline list finishes loading), also default to that
// pipeline's first stage - mirrors the extra step the original defaultToFirstPipeline did,
// which the other 4 pipeline inputs don't need.
onAutoSelect(() => {
  const [firstStage] = store.getters['kanban/getStagesForPipeline'](
    pipelineId.value
  );
  pipelineStageId.value = firstStage?.id || null;
  updateValue();
});

const selectedPipeline = computed({
  get: () =>
    pipelineOptions.value.find(option => option.id === pipelineId.value) ||
    null,
  set: option => {
    pipelineId.value = option?.id || null;
    pipelineStageId.value = null;
    updateValue();
  },
});

const stagesForPipeline = useFunctionGetter(
  'kanban/getStagesForPipeline',
  pipelineId
);
const stageOptions = computed(() => {
  if (!pipelineId.value) return [];
  return stagesForPipeline.value.map(stage => ({
    id: stage.id,
    name: stage.name,
  }));
});
const selectedStage = computed({
  get: () =>
    stageOptions.value.find(option => option.id === pipelineStageId.value) ||
    null,
  set: option => {
    pipelineStageId.value = option?.id || null;
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
  pipelineStageId.value = data.pipeline_stage_id
    ? Number(data.pipeline_stage_id)
    : null;
  assigneeMode.value = data.assignee_mode || 'none';
  teamMode.value = data.team_mode || 'none';
  title.value = data.title || '';
  value.value = data.value ?? '';
  notes.value = data.notes || '';

  if (!pipelineId.value) {
    defaultToFirstPipeline();
  }
});
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
