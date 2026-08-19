<script setup>
import { reactive, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { usePipelineLostReasonsStore } from 'dashboard/stores/pipelineLostReasons';

const props = defineProps({
  reason: { type: Object, default: null },
});
const emit = defineEmits(['close']);

const { t } = useI18n();
const lostReasonsStore = usePipelineLostReasonsStore();

const isEditing = computed(() => !!props.reason);
const form = reactive({ title: props.reason?.title || '' });

const handleSubmit = async () => {
  if (!form.title.trim()) return;
  try {
    if (isEditing.value) {
      await lostReasonsStore.update({
        id: props.reason.id,
        pipeline_lost_reason: { title: form.title },
      });
      useAlert(t('PIPELINE_LOST_REASON_MGMT.EDIT.API.SUCCESS'));
    } else {
      await lostReasonsStore.create({
        pipeline_lost_reason: { title: form.title },
      });
      useAlert(t('PIPELINE_LOST_REASON_MGMT.ADD.API.SUCCESS'));
    }
    emit('close');
  } catch {
    useAlert(
      isEditing.value
        ? t('PIPELINE_LOST_REASON_MGMT.EDIT.API.ERROR')
        : t('PIPELINE_LOST_REASON_MGMT.ADD.API.ERROR')
    );
  }
};
</script>

<template>
  <woot-modal-header
    :header-title="
      isEditing
        ? t('PIPELINE_LOST_REASON_MGMT.EDIT.TITLE')
        : t('PIPELINE_LOST_REASON_MGMT.ADD.TITLE')
    "
  />
  <form class="w-full px-6 pb-6" @submit.prevent="handleSubmit">
    <woot-input
      v-model="form.title"
      :label="t('PIPELINE_LOST_REASON_MGMT.FORM.TITLE.LABEL')"
      :placeholder="t('PIPELINE_LOST_REASON_MGMT.FORM.TITLE.PLACEHOLDER')"
      autofocus
    />
    <div class="flex justify-end gap-2 mt-4">
      <button
        type="button"
        class="px-4 py-2 text-sm text-slate-600 dark:text-slate-400 hover:bg-slate-100 dark:hover:bg-slate-700 rounded-lg transition-colors"
        @click="emit('close')"
      >
        {{ t('PIPELINE_LOST_REASON_MGMT.FORM.CANCEL') }}
      </button>
      <button
        type="submit"
        :disabled="!form.title.trim()"
        class="px-4 py-2 text-sm font-medium text-white bg-woot-500 hover:bg-woot-600 rounded-lg transition-colors disabled:opacity-50"
      >
        {{ t('PIPELINE_LOST_REASON_MGMT.FORM.SUBMIT') }}
      </button>
    </div>
  </form>
</template>
