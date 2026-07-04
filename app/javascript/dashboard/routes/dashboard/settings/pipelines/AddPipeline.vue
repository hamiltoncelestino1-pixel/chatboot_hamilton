<script setup>
import { reactive } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';

const emit = defineEmits(['close']);
const { t } = useI18n();
const store = useStore();
const uiFlags = useMapGetter('kanban/getUIFlags');

const form = reactive({ name: '', description: '' });

const handleSubmit = async () => {
  if (!form.name.trim()) return;
  try {
    await store.dispatch('kanban/createPipeline', { ...form });
    useAlert(t('PIPELINE_MGMT.ADD.API.SUCCESS'));
    emit('close');
  } catch {
    useAlert(t('PIPELINE_MGMT.ADD.API.ERROR'));
  }
};
</script>

<template>
  <woot-modal-header :header-title="t('PIPELINE_MGMT.ADD.TITLE')" />
  <form class="w-full px-6 pb-6" @submit.prevent="handleSubmit">
    <woot-input
      v-model="form.name"
      :label="t('PIPELINE_MGMT.ADD.FORM.NAME.LABEL')"
      :placeholder="t('PIPELINE_MGMT.ADD.FORM.NAME.PLACEHOLDER')"
      autofocus
    />
    <label class="block mb-4">
      <span class="text-sm font-medium text-n-slate-12 mb-1 block">
        {{ t('PIPELINE_MGMT.ADD.FORM.DESCRIPTION.LABEL') }}
      </span>
      <textarea
        v-model="form.description"
        rows="3"
        class="w-full px-3 py-2 text-sm border border-n-weak rounded-lg bg-white dark:bg-n-solid-2 text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-woot-500"
      />
    </label>
    <div class="flex justify-end gap-2 mt-4">
      <button
        type="button"
        class="px-4 py-2 text-sm text-slate-600 dark:text-slate-400 hover:bg-slate-100 dark:hover:bg-slate-700 rounded-lg transition-colors"
        @click="emit('close')"
      >
        {{ t('PIPELINE_MGMT.ADD.CANCEL') }}
      </button>
      <button
        type="submit"
        :disabled="uiFlags.isCreating || !form.name.trim()"
        class="px-4 py-2 text-sm font-medium text-white bg-woot-500 hover:bg-woot-600 rounded-lg transition-colors disabled:opacity-50"
      >
        {{ uiFlags.isCreating ? '...' : t('PIPELINE_MGMT.ADD.SUBMIT') }}
      </button>
    </div>
  </form>
</template>
