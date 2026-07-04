<script setup>
import { computed, onBeforeMount, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { useStore, useStoreGetters } from 'dashboard/composables/store';
import TabBar from 'dashboard/components-next/tabbar/TabBar.vue';
import SettingsLayout from '../SettingsLayout.vue';
import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';
import PipelineStagesSection from './PipelineStagesSection.vue';
import PipelineLabelsSection from './PipelineLabelsSection.vue';
import PipelineMembersSection from './PipelineMembersSection.vue';

const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const store = useStore();
const getters = useStoreGetters();

const pipelineId = computed(() => Number(route.params.pipelineId));
const pipeline = computed(() =>
  getters['kanban/getPipelines'].value.find(p => p.id === pipelineId.value)
);

const selectedTabIndex = ref(0);
const tabs = computed(() => [
  { key: 0, label: t('PIPELINE_MGMT.DETAIL.TABS.STAGES') },
  { key: 1, label: t('PIPELINE_MGMT.DETAIL.TABS.LABELS') },
  { key: 2, label: t('PIPELINE_MGMT.DETAIL.TABS.AGENTS') },
]);

onBeforeMount(async () => {
  await store.dispatch('kanban/fetchPipelines');
  store.dispatch('pipelineMembers/get', { pipelineId: pipelineId.value });
});
</script>

<template>
  <SettingsLayout>
    <template #header>
      <BaseSettingsHeader
        :title="pipeline?.name || ''"
        :description="pipeline?.description || ''"
      >
        <template #tabs>
          <TabBar
            :tabs="tabs"
            :initial-active-tab="selectedTabIndex"
            @tab-changed="tab => (selectedTabIndex = tab.key)"
          />
        </template>
        <template #actions>
          <button
            class="flex items-center gap-1.5 px-3 py-1.5 text-sm text-slate-600 dark:text-slate-400 hover:bg-slate-100 dark:hover:bg-slate-700 rounded-lg transition-colors"
            @click="router.push({ name: 'pipelines_list' })"
          >
            <span class="i-lucide-arrow-left size-4" />
            {{ t('PIPELINE_MGMT.BACK') }}
          </button>
        </template>
      </BaseSettingsHeader>
    </template>
    <template #body>
      <PipelineStagesSection
        v-if="selectedTabIndex === 0"
        :pipeline-id="pipelineId"
      />
      <PipelineLabelsSection v-if="selectedTabIndex === 1" />
      <PipelineMembersSection
        v-if="selectedTabIndex === 2"
        :pipeline-id="pipelineId"
      />
    </template>
  </SettingsLayout>
</template>
