<script setup>
import { ref, computed, onMounted, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { usePipelineLostReasonsStore } from 'dashboard/stores/pipelineLostReasons';
import { useLostReasonPrompt } from 'dashboard/composables/useLostReasonPrompt';

const { t } = useI18n();
const { isOpen, confirmLostReason, cancelLostReason } = useLostReasonPrompt();

const lostReasonsStore = usePipelineLostReasonsStore();
const reasons = computed(() => lostReasonsStore.getRecords);

const selectedReasonId = ref(null);

watch(isOpen, open => {
  if (!open) return;
  selectedReasonId.value = null;
  lostReasonsStore.get();
});

onMounted(() => {
  lostReasonsStore.get();
});

const handleConfirm = () => {
  if (!selectedReasonId.value) return;
  confirmLostReason(selectedReasonId.value);
};
</script>

<template>
  <Teleport to="body">
    <div
      v-if="isOpen"
      class="fixed inset-0 z-50 flex items-center justify-center"
      @click.self="cancelLostReason"
    >
      <div class="fixed inset-0 bg-black/30" @click="cancelLostReason" />

      <div
        class="relative w-full max-w-sm bg-white dark:bg-slate-800 rounded-xl shadow-xl z-10 p-5"
      >
        <h3
          class="text-base font-semibold text-slate-800 dark:text-slate-100 mb-1"
        >
          {{ t('KANBAN.LOST_REASON.MODAL_TITLE') }}
        </h3>
        <p class="text-sm text-slate-500 dark:text-slate-400 mb-4">
          {{ t('KANBAN.LOST_REASON.MODAL_DESCRIPTION') }}
        </p>

        <select
          v-model="selectedReasonId"
          class="w-full px-3 py-2 text-sm border border-slate-200 dark:border-slate-600 rounded-lg bg-white dark:bg-slate-700 text-slate-800 dark:text-slate-100 focus:outline-none focus:ring-2 focus:ring-woot-500"
        >
          <option :value="null" disabled>
            {{ t('KANBAN.LOST_REASON.SELECT_PLACEHOLDER') }}
          </option>
          <option v-for="reason in reasons" :key="reason.id" :value="reason.id">
            {{ reason.title }}
          </option>
        </select>

        <div class="flex justify-end gap-2 mt-5">
          <button
            class="px-4 py-2 text-sm text-slate-600 dark:text-slate-400 hover:bg-slate-100 dark:hover:bg-slate-700 rounded-lg transition-colors"
            @click="cancelLostReason"
          >
            {{ t('KANBAN.ITEM.CANCEL') }}
          </button>
          <button
            class="px-4 py-2 text-sm font-medium text-white bg-woot-500 hover:bg-woot-600 rounded-lg transition-colors disabled:opacity-50"
            :disabled="!selectedReasonId"
            @click="handleConfirm"
          >
            {{ t('KANBAN.LOST_REASON.CONFIRM') }}
          </button>
        </div>
      </div>
    </div>
  </Teleport>
</template>
