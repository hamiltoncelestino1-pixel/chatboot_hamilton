<script setup>
import { computed, onBeforeMount, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useStoreGetters, useStore } from 'dashboard/composables/store';
import { picoSearch } from '@scmmishra/pico-search';
import { useRouter } from 'vue-router';

import AddPipeline from './AddPipeline.vue';
import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';
import SettingsLayout from '../SettingsLayout.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import {
  BaseTable,
  BaseTableRow,
  BaseTableCell,
} from 'dashboard/components-next/table';

const { t } = useI18n();
const router = useRouter();
const getters = useStoreGetters();
const store = useStore();

const showAddPopup = ref(false);
const showDeletePopup = ref(false);
const selectedPipeline = ref({});
const searchQuery = ref('');
const loading = ref({});

const pipelines = computed(() => getters['kanban/getPipelines'].value);
const uiFlags = computed(() => getters['kanban/getUIFlags'].value);

const filteredPipelines = computed(() => {
  const query = searchQuery.value.trim();
  if (!query) return pipelines.value;
  return picoSearch(pipelines.value, query, [
    { name: 'name', weight: 4 },
    'description',
  ]);
});

const stagesCount = pipeline =>
  getters['kanban/getStagesForPipeline'].value(pipeline.id)?.length || 0;

onBeforeMount(() => {
  store.dispatch('kanban/fetchPipelines');
});

const openAddPopup = () => {
  showAddPopup.value = true;
};
const hideAddPopup = () => {
  showAddPopup.value = false;
};

const goToDetail = pipeline => {
  router.push({ name: 'pipelines_show', params: { pipelineId: pipeline.id } });
};

const openDeletePopup = pipeline => {
  selectedPipeline.value = pipeline;
  showDeletePopup.value = true;
};
const closeDeletePopup = () => {
  showDeletePopup.value = false;
};

const confirmDeletion = async () => {
  loading.value[selectedPipeline.value.id] = true;
  closeDeletePopup();
  try {
    await store.dispatch('kanban/deletePipeline', selectedPipeline.value.id);
    useAlert(t('PIPELINE_MGMT.DELETE.API.SUCCESS'));
  } catch {
    useAlert(t('PIPELINE_MGMT.DELETE.API.ERROR'));
  } finally {
    loading.value[selectedPipeline.value.id] = false;
  }
};

const deleteMessage = computed(
  () =>
    ` ${selectedPipeline.value.name}? ${t('PIPELINE_MGMT.DELETE.CONFIRM.CASCADE_WARNING', { stages: stagesCount(selectedPipeline.value) })}`
);

const tableHeaders = computed(() => [
  t('PIPELINE_MGMT.LIST.TABLE_HEADER.NAME'),
  t('PIPELINE_MGMT.LIST.TABLE_HEADER.STAGES'),
  t('PIPELINE_MGMT.LIST.TABLE_HEADER.ACTION'),
]);
</script>

<template>
  <SettingsLayout
    :is-loading="uiFlags.isFetchingPipelines"
    :loading-message="t('PIPELINE_MGMT.LOADING')"
    :no-records-found="!pipelines.length"
    :no-records-message="t('PIPELINE_MGMT.LIST.404')"
  >
    <template #header>
      <BaseSettingsHeader
        v-model:search-query="searchQuery"
        :title="t('PIPELINE_MGMT.HEADER')"
        :description="t('PIPELINE_MGMT.DESCRIPTION')"
        :search-placeholder="t('PIPELINE_MGMT.SEARCH_PLACEHOLDER')"
      >
        <template #actions>
          <Button
            :label="t('PIPELINE_MGMT.LOST_REASONS_LINK')"
            variant="ghost"
            size="sm"
            @click="router.push({ name: 'pipeline_lost_reasons_list' })"
          />
          <Button
            :label="t('PIPELINE_MGMT.HEADER_BTN_TXT')"
            size="sm"
            @click="openAddPopup"
          />
        </template>
      </BaseSettingsHeader>
    </template>
    <template #body>
      <BaseTable :headers="tableHeaders" :items="filteredPipelines">
        <template #row="{ items }">
          <BaseTableRow
            v-for="pipeline in items"
            :key="pipeline.id"
            :item="pipeline"
          >
            <template #default>
              <BaseTableCell>
                <button
                  class="text-left text-n-blue-11 hover:underline"
                  @click="goToDetail(pipeline)"
                >
                  {{ pipeline.name }}
                </button>
              </BaseTableCell>
              <BaseTableCell>
                <span class="text-body-main text-n-slate-11">
                  {{ stagesCount(pipeline) }}
                </span>
              </BaseTableCell>
              <BaseTableCell align="end">
                <div class="flex gap-3 justify-end flex-shrink-0">
                  <Button
                    v-tooltip.top="t('PIPELINE_MGMT.FORM.EDIT')"
                    icon="i-woot-edit-pen"
                    slate
                    sm
                    @click="goToDetail(pipeline)"
                  />
                  <Button
                    v-tooltip.top="t('PIPELINE_MGMT.FORM.DELETE')"
                    icon="i-woot-bin"
                    slate
                    sm
                    :is-loading="loading[pipeline.id]"
                    class="hover:enabled:text-n-ruby-11 hover:enabled:bg-n-ruby-2"
                    @click="openDeletePopup(pipeline)"
                  />
                </div>
              </BaseTableCell>
            </template>
          </BaseTableRow>
        </template>
      </BaseTable>
    </template>

    <woot-modal v-model:show="showAddPopup" :on-close="hideAddPopup">
      <AddPipeline @close="hideAddPopup" />
    </woot-modal>

    <woot-delete-modal
      v-model:show="showDeletePopup"
      :on-close="closeDeletePopup"
      :on-confirm="confirmDeletion"
      :title="t('PIPELINE_MGMT.DELETE.CONFIRM.TITLE')"
      :message="t('PIPELINE_MGMT.DELETE.CONFIRM.MESSAGE')"
      :message-value="deleteMessage"
      :confirm-text="t('PIPELINE_MGMT.DELETE.CONFIRM.YES')"
      :reject-text="t('PIPELINE_MGMT.DELETE.CONFIRM.NO')"
    />
  </SettingsLayout>
</template>
