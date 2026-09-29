<script setup>
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { usePipelineSelector } from 'dashboard/composables/usePipelineSelector';
import { useNumberFormatter } from 'shared/composables/useNumberFormatter';
import PipelineReportsAPI from 'dashboard/api/pipelineReports';
import ReportHeader from './components/ReportHeader.vue';
import ReportMetricCard from './components/ReportMetricCard.vue';
import SingleSelect from 'dashboard/components-next/filter/inputs/SingleSelect.vue';
import BarChart from 'shared/components/charts/BarChart.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';

const SECONDS_IN_A_DAY = 86400;

const { t } = useI18n();
const { formatCurrency } = useNumberFormatter();

const { pipelineId, pipelineOptions, onAutoSelect } = usePipelineSelector();

const isFetching = ref(false);
const report = ref(null);

const fetchReport = async () => {
  if (!pipelineId.value) return;
  isFetching.value = true;
  try {
    const { data } = await PipelineReportsAPI.getFunnelReport(pipelineId.value);
    report.value = data;
  } finally {
    isFetching.value = false;
  }
};

const selectedPipeline = computed({
  get: () =>
    pipelineOptions.value.find(option => option.id === pipelineId.value) ||
    null,
  set: option => {
    pipelineId.value = option?.id || null;
    // Manual pipeline change refetches here, matching how every other usePipelineSelector
    // consumer wires it (e.g. AutomationActionPipelineStageInput). Watching pipelineId
    // instead would double-fetch on the initial auto-select, since defaultToFirstPipeline
    // sets the ref and synchronously calls the onAutoSelect callback before the watch runs.
    fetchReport();
  },
});

onAutoSelect(fetchReport);

const openValueFormatted = computed(() =>
  formatCurrency(report.value?.open_value || 0)
);

const stageNames = computed(() =>
  Object.keys(report.value?.stage_distribution || {})
);

const hasStageData = computed(() => stageNames.value.length > 0);

const distributionCollection = computed(() => ({
  labels: stageNames.value,
  datasets: [
    {
      label: t('FUNNEL_REPORTS.STAGE_DISTRIBUTION.DATASET_LABEL'),
      backgroundColor: '#1f93ff',
      data: stageNames.value.map(name => report.value.stage_distribution[name]),
    },
  ],
}));

const avgTimeCollection = computed(() => ({
  labels: stageNames.value,
  datasets: [
    {
      label: t('FUNNEL_REPORTS.AVG_TIME.DATASET_LABEL'),
      backgroundColor: '#1f9e51',
      data: stageNames.value.map(name => {
        const seconds = report.value.avg_time_in_stage[name] || 0;
        return Number((seconds / SECONDS_IN_A_DAY).toFixed(1));
      }),
    },
  ],
}));
</script>

<template>
  <ReportHeader
    :header-title="t('FUNNEL_REPORTS.HEADER')"
    :header-description="t('FUNNEL_REPORTS.DESCRIPTION')"
  >
    <SingleSelect
      v-model="selectedPipeline"
      :options="pipelineOptions"
      :placeholder="t('FUNNEL_REPORTS.PIPELINE_PLACEHOLDER')"
      disable-search
    />
  </ReportHeader>

  <div v-if="isFetching" class="flex items-center justify-center py-20">
    <Spinner />
  </div>

  <div
    v-else-if="!pipelineId"
    class="text-center text-n-slate-11 text-sm py-20"
  >
    {{ t('FUNNEL_REPORTS.NO_PIPELINE_SELECTED') }}
  </div>

  <div v-else class="flex flex-col gap-6">
    <div
      class="p-4 rounded-xl outline outline-1 outline-n-container bg-n-solid-2"
    >
      <ReportMetricCard
        :label="t('FUNNEL_REPORTS.OPEN_VALUE.LABEL')"
        :value="openValueFormatted"
        :info-text="t('FUNNEL_REPORTS.OPEN_VALUE.INFO_TEXT')"
      />
    </div>

    <div v-if="!hasStageData" class="text-center text-n-slate-10 text-sm py-10">
      {{ t('REPORT.NO_ENOUGH_DATA') }}
    </div>

    <template v-else>
      <div
        class="flex items-start gap-2 p-3 rounded-lg bg-n-alpha-1 text-n-slate-11 text-sm"
      >
        <span class="i-lucide-info flex-shrink-0 mt-0.5 size-4" />
        <span>{{ t('FUNNEL_REPORTS.SNAPSHOT_NOTE') }}</span>
      </div>

      <div
        class="p-4 rounded-xl outline outline-1 outline-n-container bg-n-solid-2"
      >
        <h3 class="text-sm font-medium text-n-slate-11 mb-3">
          {{ t('FUNNEL_REPORTS.STAGE_DISTRIBUTION.TITLE') }}
        </h3>
        <div class="h-72">
          <BarChart :collection="distributionCollection" />
        </div>
      </div>

      <div
        class="p-4 rounded-xl outline outline-1 outline-n-container bg-n-solid-2"
      >
        <h3 class="text-sm font-medium text-n-slate-11 mb-3">
          {{ t('FUNNEL_REPORTS.AVG_TIME.TITLE') }}
        </h3>
        <div class="h-72">
          <BarChart :collection="avgTimeCollection" />
        </div>
      </div>
    </template>
  </div>
</template>
