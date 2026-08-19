<script setup>
import { computed, onBeforeMount, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import { usePipelineLostReasonsStore } from 'dashboard/stores/pipelineLostReasons';
import { picoSearch } from '@scmmishra/pico-search';

import LostReasonForm from './LostReasonForm.vue';
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
const lostReasonsStore = usePipelineLostReasonsStore();
const reasons = computed(() => lostReasonsStore.getRecords);
const uiFlags = computed(() => lostReasonsStore.getUIFlags);

const showFormPopup = ref(false);
const showDeletePopup = ref(false);
const selectedReason = ref(null);
const searchQuery = ref('');
const loading = ref({});

const filteredReasons = computed(() => {
  const query = searchQuery.value.trim();
  if (!query) return reasons.value;
  return picoSearch(reasons.value, query, [{ name: 'title', weight: 4 }]);
});

onBeforeMount(() => {
  lostReasonsStore.get();
});

const openAddPopup = () => {
  selectedReason.value = null;
  showFormPopup.value = true;
};
const openEditPopup = reason => {
  selectedReason.value = reason;
  showFormPopup.value = true;
};
const closeFormPopup = () => {
  showFormPopup.value = false;
};

const openDeletePopup = reason => {
  selectedReason.value = reason;
  showDeletePopup.value = true;
};
const closeDeletePopup = () => {
  showDeletePopup.value = false;
};

const confirmDeletion = async () => {
  loading.value[selectedReason.value.id] = true;
  closeDeletePopup();
  try {
    await lostReasonsStore.delete(selectedReason.value.id);
    useAlert(t('PIPELINE_LOST_REASON_MGMT.DELETE.API.SUCCESS'));
  } catch {
    useAlert(t('PIPELINE_LOST_REASON_MGMT.DELETE.API.ERROR'));
  } finally {
    loading.value[selectedReason.value.id] = false;
  }
};

const tableHeaders = computed(() => [
  t('PIPELINE_LOST_REASON_MGMT.LIST.TABLE_HEADER.TITLE'),
  t('PIPELINE_LOST_REASON_MGMT.LIST.TABLE_HEADER.ACTION'),
]);
</script>

<template>
  <SettingsLayout
    :is-loading="uiFlags.fetchingList"
    :loading-message="t('PIPELINE_LOST_REASON_MGMT.LOADING')"
    :no-records-found="!reasons.length"
    :no-records-message="t('PIPELINE_LOST_REASON_MGMT.LIST.404')"
  >
    <template #header>
      <BaseSettingsHeader
        v-model:search-query="searchQuery"
        :title="t('PIPELINE_LOST_REASON_MGMT.HEADER')"
        :description="t('PIPELINE_LOST_REASON_MGMT.DESCRIPTION')"
        :search-placeholder="t('PIPELINE_LOST_REASON_MGMT.SEARCH_PLACEHOLDER')"
      >
        <template #actions>
          <button
            class="flex items-center gap-1.5 px-3 py-1.5 text-sm text-slate-600 dark:text-slate-400 hover:bg-slate-100 dark:hover:bg-slate-700 rounded-lg transition-colors"
            @click="router.push({ name: 'pipelines_list' })"
          >
            <span class="i-lucide-arrow-left size-4" />
            {{ t('PIPELINE_LOST_REASON_MGMT.BACK') }}
          </button>
          <Button
            :label="t('PIPELINE_LOST_REASON_MGMT.HEADER_BTN_TXT')"
            size="sm"
            @click="openAddPopup"
          />
        </template>
      </BaseSettingsHeader>
    </template>
    <template #body>
      <BaseTable :headers="tableHeaders" :items="filteredReasons">
        <template #row="{ items }">
          <BaseTableRow v-for="reason in items" :key="reason.id" :item="reason">
            <template #default>
              <BaseTableCell>
                <span class="text-body-main text-n-slate-12">
                  {{ reason.title }}
                </span>
              </BaseTableCell>
              <BaseTableCell align="end">
                <div class="flex gap-3 justify-end flex-shrink-0">
                  <Button
                    v-tooltip.top="t('PIPELINE_LOST_REASON_MGMT.FORM.EDIT')"
                    icon="i-woot-edit-pen"
                    slate
                    sm
                    @click="openEditPopup(reason)"
                  />
                  <Button
                    v-tooltip.top="t('PIPELINE_LOST_REASON_MGMT.FORM.DELETE')"
                    icon="i-woot-bin"
                    slate
                    sm
                    :is-loading="loading[reason.id]"
                    class="hover:enabled:text-n-ruby-11 hover:enabled:bg-n-ruby-2"
                    @click="openDeletePopup(reason)"
                  />
                </div>
              </BaseTableCell>
            </template>
          </BaseTableRow>
        </template>
      </BaseTable>
    </template>

    <woot-modal v-model:show="showFormPopup" :on-close="closeFormPopup">
      <LostReasonForm
        v-if="showFormPopup"
        :reason="selectedReason"
        @close="closeFormPopup"
      />
    </woot-modal>

    <woot-delete-modal
      v-model:show="showDeletePopup"
      :on-close="closeDeletePopup"
      :on-confirm="confirmDeletion"
      :title="t('PIPELINE_LOST_REASON_MGMT.DELETE.CONFIRM.TITLE')"
      :message="t('PIPELINE_LOST_REASON_MGMT.DELETE.CONFIRM.MESSAGE')"
      :message-value="selectedReason ? ` ${selectedReason.title}?` : ''"
      :confirm-text="t('PIPELINE_LOST_REASON_MGMT.DELETE.CONFIRM.YES')"
      :reject-text="t('PIPELINE_LOST_REASON_MGMT.DELETE.CONFIRM.NO')"
    />
  </SettingsLayout>
</template>
