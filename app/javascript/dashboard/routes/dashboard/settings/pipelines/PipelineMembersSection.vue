<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useStore, useStoreGetters } from 'dashboard/composables/store';
import TagInput from 'dashboard/components-next/taginput/TagInput.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import SettingsToggleSection from 'dashboard/components-next/Settings/SettingsToggleSection.vue';

const props = defineProps({
  pipelineId: { type: Number, required: true },
});

const { t } = useI18n();
const store = useStore();
const getters = useStoreGetters();

const selectedAgentIds = ref([]);
const isUpdating = ref(false);
const enableAutoAssignment = ref(false);
const maxAssignmentLimit = ref(0);
const syncAssignments = ref(false);

const allAgents = computed(() => getters['agents/getAgents'].value);
const currentMembers = computed(
  () =>
    getters['pipelineMembers/getPipelineMembers'].value(props.pipelineId) || []
);
const pipeline = computed(() =>
  getters['kanban/getPipelines'].value.find(p => p.id === props.pipelineId)
);

const selectedAgentNames = computed(() =>
  selectedAgentIds.value.map(
    id => allAgents.value.find(a => a.id === id)?.name ?? ''
  )
);

const agentMenuItems = computed(() =>
  allAgents.value
    .filter(({ id }) => !selectedAgentIds.value.includes(id))
    .map(({ id, name, thumbnail, avatar_url }) => ({
      label: name,
      value: id,
      action: 'select',
      thumbnail: { name, src: thumbnail || avatar_url || '' },
    }))
);

const handleAgentAdd = ({ value }) => {
  if (!selectedAgentIds.value.includes(value)) {
    selectedAgentIds.value.push(value);
  }
};

const handleAgentRemove = index => {
  selectedAgentIds.value.splice(index, 1);
};

onMounted(async () => {
  await store.dispatch('agents/get');
  await store.dispatch('pipelineMembers/get', { pipelineId: props.pipelineId });
  selectedAgentIds.value = currentMembers.value.map(a => a.id);

  const p = pipeline.value;
  if (p) {
    enableAutoAssignment.value = p.enable_auto_assignment ?? false;
    maxAssignmentLimit.value = p.max_assignment_limit ?? 0;
    syncAssignments.value = p.sync_assignments ?? false;
  }
});

const handleUpdate = async () => {
  isUpdating.value = true;
  try {
    await store.dispatch('pipelineMembers/update', {
      pipelineId: props.pipelineId,
      agentIds: selectedAgentIds.value,
    });
    useAlert(t('PIPELINE_MGMT.AGENTS.API.SUCCESS'));
  } catch {
    useAlert(t('PIPELINE_MGMT.AGENTS.API.ERROR'));
  } finally {
    isUpdating.value = false;
  }
};

const handleToggleAutoAssignment = async value => {
  try {
    await store.dispatch('kanban/updatePipeline', {
      id: props.pipelineId,
      enable_auto_assignment: value,
    });
    enableAutoAssignment.value = value;
  } catch {
    enableAutoAssignment.value = !value;
    useAlert(t('PIPELINE_MGMT.AGENTS.API.ERROR'));
  }
};

const handleToggleSyncAssignments = async value => {
  try {
    await store.dispatch('kanban/updatePipeline', {
      id: props.pipelineId,
      sync_assignments: value,
    });
    syncAssignments.value = value;
  } catch {
    syncAssignments.value = !value;
    useAlert(t('PIPELINE_MGMT.AGENTS.API.ERROR'));
  }
};

const handleUpdateMaxAssignmentLimit = async () => {
  const newLimit = Number(maxAssignmentLimit.value) || 0;
  try {
    await store.dispatch('kanban/updatePipeline', {
      id: props.pipelineId,
      max_assignment_limit: newLimit,
    });
    maxAssignmentLimit.value = newLimit;
  } catch {
    maxAssignmentLimit.value = pipeline.value?.max_assignment_limit ?? 0;
    useAlert(t('PIPELINE_MGMT.AGENTS.API.ERROR'));
  }
};
</script>

<template>
  <div class="space-y-4 p-1">
    <p class="text-sm text-n-slate-11">
      {{ t('PIPELINE_MGMT.AGENTS.DESCRIPTION') }}
    </p>
    <TagInput
      :model-value="selectedAgentNames"
      :placeholder="t('PIPELINE_MGMT.AGENTS.SEARCH_PLACEHOLDER')"
      :menu-items="agentMenuItems"
      show-dropdown
      skip-label-dedup
      :auto-open-dropdown="false"
      @add="handleAgentAdd"
      @remove="handleAgentRemove"
    />
    <NextButton
      :label="t('PIPELINE_MGMT.AGENTS.UPDATE')"
      :is-loading="isUpdating"
      @click="handleUpdate"
    />

    <SettingsToggleSection
      v-model="enableAutoAssignment"
      :header="t('PIPELINE_MGMT.AGENTS.AUTO_ASSIGNMENT.TITLE')"
      :description="t('PIPELINE_MGMT.AGENTS.AUTO_ASSIGNMENT.DESCRIPTION')"
      @update:model-value="handleToggleAutoAssignment"
    >
      <template #editor>
        <div class="space-y-1">
          <label class="text-sm font-medium text-n-slate-12">
            {{ t('PIPELINE_MGMT.AGENTS.AUTO_ASSIGNMENT.MAX_LIMIT_LABEL') }}
          </label>
          <input
            v-model.number="maxAssignmentLimit"
            type="number"
            min="0"
            class="w-full rounded-lg border border-n-weak bg-n-alpha-1 px-3 py-2 text-sm text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-woot-500"
            @blur="handleUpdateMaxAssignmentLimit"
          />
          <p class="text-xs text-n-slate-11">
            {{ t('PIPELINE_MGMT.AGENTS.AUTO_ASSIGNMENT.MAX_LIMIT_HELP') }}
          </p>
        </div>
      </template>
    </SettingsToggleSection>

    <SettingsToggleSection
      v-model="syncAssignments"
      :header="t('PIPELINE_MGMT.AGENTS.SYNC_ASSIGNMENTS.TITLE')"
      :description="t('PIPELINE_MGMT.AGENTS.SYNC_ASSIGNMENTS.DESCRIPTION')"
      @update:model-value="handleToggleSyncAssignments"
    />
  </div>
</template>
