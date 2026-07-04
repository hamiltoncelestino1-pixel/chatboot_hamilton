<script setup>
import { computed, onBeforeMount, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useStore, useMapGetter } from 'dashboard/composables/store';

import AddLabel from '../labels/AddLabel.vue';
import EditLabel from '../labels/EditLabel.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import {
  BaseTable,
  BaseTableRow,
  BaseTableCell,
} from 'dashboard/components-next/table';

const { t } = useI18n();
const store = useStore();

const showAddPopup = ref(false);
const showEditPopup = ref(false);
const showDeletePopup = ref(false);
const selectedLabel = ref({});
const loading = ref({});

const pipelineLabels = useMapGetter('labels/getPipelineLabels');

const openEditPopup = label => {
  selectedLabel.value = label;
  showEditPopup.value = true;
};

const openDeletePopup = label => {
  selectedLabel.value = label;
  showDeletePopup.value = true;
};

const closeDeletePopup = () => {
  showDeletePopup.value = false;
};

const deleteLabel = async id => {
  try {
    await store.dispatch('labels/delete', id);
    useAlert(t('LABEL_MGMT.DELETE.API.SUCCESS_MESSAGE'));
  } catch (error) {
    useAlert(error?.message || t('LABEL_MGMT.DELETE.API.ERROR_MESSAGE'));
  } finally {
    loading.value[selectedLabel.value.id] = false;
  }
};

const confirmDeletion = () => {
  loading.value[selectedLabel.value.id] = true;
  closeDeletePopup();
  deleteLabel(selectedLabel.value.id);
};

onBeforeMount(() => {
  store.dispatch('labels/get');
});

const tableHeaders = computed(() => [
  t('LABEL_MGMT.LIST.TABLE_HEADER.NAME'),
  t('LABEL_MGMT.LIST.TABLE_HEADER.COLOR'),
  t('LABEL_MGMT.LIST.TABLE_HEADER.ACTION'),
]);
</script>

<template>
  <div class="space-y-4">
    <div class="flex justify-end">
      <Button
        :label="t('LABEL_MGMT.HEADER_BTN_TXT')"
        size="sm"
        @click="showAddPopup = true"
      />
    </div>

    <BaseTable :headers="tableHeaders" :items="pipelineLabels">
      <template #row="{ items }">
        <BaseTableRow v-for="label in items" :key="label.title" :item="label">
          <template #default>
            <BaseTableCell>
              <span class="text-body-main text-n-slate-12">{{
                label.title
              }}</span>
            </BaseTableCell>
            <BaseTableCell>
              <div class="flex items-center gap-2">
                <span
                  class="w-4 h-4 rounded border border-n-weak"
                  :style="{ backgroundColor: label.color }"
                />
                <span class="text-body-main text-n-slate-12">{{
                  label.color
                }}</span>
              </div>
            </BaseTableCell>
            <BaseTableCell align="end">
              <div class="flex gap-3 justify-end flex-shrink-0">
                <Button
                  v-tooltip.top="t('LABEL_MGMT.FORM.EDIT')"
                  icon="i-woot-edit-pen"
                  slate
                  sm
                  @click="openEditPopup(label)"
                />
                <Button
                  v-tooltip.top="t('LABEL_MGMT.FORM.DELETE')"
                  icon="i-woot-bin"
                  slate
                  sm
                  :is-loading="loading[label.id]"
                  class="hover:enabled:text-n-ruby-11 hover:enabled:bg-n-ruby-2"
                  @click="openDeletePopup(label)"
                />
              </div>
            </BaseTableCell>
          </template>
        </BaseTableRow>
      </template>
    </BaseTable>

    <woot-modal
      v-model:show="showAddPopup"
      :on-close="() => (showAddPopup = false)"
    >
      <AddLabel
        fixed-label-type="pipeline_label"
        @close="showAddPopup = false"
      />
    </woot-modal>

    <woot-modal
      v-model:show="showEditPopup"
      :on-close="() => (showEditPopup = false)"
    >
      <EditLabel
        :selected-response="selectedLabel"
        @close="showEditPopup = false"
      />
    </woot-modal>

    <woot-delete-modal
      v-model:show="showDeletePopup"
      :on-close="closeDeletePopup"
      :on-confirm="confirmDeletion"
      :title="t('LABEL_MGMT.DELETE.CONFIRM.TITLE')"
      :message="t('LABEL_MGMT.DELETE.CONFIRM.MESSAGE')"
      :message-value="` ${selectedLabel.title}?`"
      :confirm-text="t('LABEL_MGMT.DELETE.CONFIRM.YES')"
      :reject-text="t('LABEL_MGMT.DELETE.CONFIRM.NO')"
    />
  </div>
</template>
