<script setup>
import { computed, onMounted, reactive, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import DatePicker from 'vue-datepicker-next';
import MultiselectDropdown from 'shared/components/ui/MultiselectDropdown.vue';

const props = defineProps({
  contactId: { type: Number, required: true },
  conversationId: { type: [Number, String], default: null },
  pipelineItemId: { type: [Number, String], default: null },
  task: { type: Object, default: null },
});

const emit = defineEmits(['close']);

const { t } = useI18n();
const store = useStore();
const agents = useMapGetter('agents/getAgents');
const currentUser = useMapGetter('getCurrentUser');

const isEditMode = computed(() => !!props.task);

const form = reactive({ title: props.task?.title || '' });
const dueDate = ref(props.task ? new Date(props.task.due_date * 1000) : null);
const assignee = ref(props.task?.assignee || null);
const recurrenceInterval = ref(props.task?.recurrence_interval || '');
const isSubmitting = ref(false);

onMounted(() => {
  store.dispatch('agents/get');
  if (!isEditMode.value) {
    assignee.value = currentUser.value || null;
  }
});

const showPastDueWarning = computed(() => {
  if (!dueDate.value) return false;
  const threeDaysAgo = Date.now() - 3 * 24 * 60 * 60 * 1000;
  return dueDate.value.getTime() < threeDaysAgo;
});

const onAssignAgent = selected => {
  assignee.value = selected || null;
};

const isFormValid = computed(() => !!form.title && !!dueDate.value);

const handleSubmit = async () => {
  if (!isFormValid.value) return;
  isSubmitting.value = true;
  try {
    if (isEditMode.value) {
      await store.dispatch('tasks/update', {
        id: props.task.id,
        title: form.title,
        due_date: dueDate.value.toISOString(),
        assignee_id: assignee.value?.id || null,
        recurrence_interval: recurrenceInterval.value || null,
      });
      useAlert(t('TASKS.API.UPDATE_SUCCESS'));
    } else {
      await store.dispatch('tasks/create', {
        title: form.title,
        due_date: dueDate.value.toISOString(),
        contact_id: props.contactId,
        conversation_id: props.conversationId || null,
        pipeline_item_id: props.pipelineItemId || null,
        assignee_id: assignee.value?.id || null,
        recurrence_interval: recurrenceInterval.value || null,
      });
      useAlert(t('TASKS.API.CREATE_SUCCESS'));
    }
    emit('close');
  } catch (error) {
    useAlert(error.message || t('TASKS.API.ERROR'));
  } finally {
    isSubmitting.value = false;
  }
};
</script>

<template>
  <Teleport to="body">
    <div class="fixed inset-0 z-50 flex items-center justify-center">
      <div class="fixed inset-0 bg-black/30" @click="emit('close')" />

      <div
        class="relative w-full max-w-md bg-white dark:bg-slate-800 rounded-xl shadow-xl z-10"
      >
        <div
          class="flex items-center justify-between px-6 py-4 border-b border-slate-100 dark:border-slate-700"
        >
          <h3
            class="text-base font-semibold text-slate-800 dark:text-slate-100"
          >
            {{ t(isEditMode ? 'TASKS.EDIT' : 'TASKS.CREATE') }}
          </h3>
          <button
            class="text-slate-400 hover:text-slate-600 dark:hover:text-slate-200 transition-colors"
            @click="emit('close')"
          >
            <span class="i-lucide-x size-5" />
          </button>
        </div>

        <div class="px-6 py-4 space-y-4">
          <div>
            <label
              class="block text-sm font-medium text-slate-700 dark:text-slate-300 mb-1"
            >
              {{ t('TASKS.TITLE_LABEL') }}
              <span class="text-red-500">*</span>
            </label>
            <input
              v-model="form.title"
              type="text"
              class="w-full px-3 py-2 text-sm border border-slate-200 dark:border-slate-600 rounded-lg bg-white dark:bg-slate-700 text-slate-800 dark:text-slate-100 focus:outline-none focus:ring-2 focus:ring-woot-500"
              :placeholder="t('TASKS.TITLE_PLACEHOLDER')"
            />
          </div>

          <div>
            <label
              class="block text-sm font-medium text-slate-700 dark:text-slate-300 mb-1"
            >
              {{ t('TASKS.DUE_DATE_LABEL') }}
              <span class="text-red-500">*</span>
            </label>
            <DatePicker
              v-model:value="dueDate"
              type="datetime"
              confirm
              :clearable="false"
              :editable="false"
              :placeholder="t('TASKS.DUE_DATE_PLACEHOLDER')"
              class="w-full"
            />
            <p v-if="showPastDueWarning" class="text-xs text-n-amber-11 mt-1">
              {{ t('TASKS.PAST_DUE_WARNING') }}
            </p>
          </div>

          <div>
            <label
              class="block text-sm font-medium text-slate-700 dark:text-slate-300 mb-1"
            >
              {{ t('TASKS.ASSIGNEE_LABEL') }}
            </label>
            <MultiselectDropdown
              :options="agents"
              :selected-item="assignee"
              :multiselector-title="t('AGENT_MGMT.MULTI_SELECTOR.TITLE.AGENT')"
              :multiselector-placeholder="t('TASKS.ASSIGNEE_PLACEHOLDER')"
              :no-search-result="
                t('AGENT_MGMT.MULTI_SELECTOR.SEARCH.NO_RESULTS.AGENT')
              "
              :input-placeholder="
                t('AGENT_MGMT.MULTI_SELECTOR.SEARCH.PLACEHOLDER.AGENT')
              "
              @select="onAssignAgent"
            />
          </div>

          <div>
            <label
              class="block text-sm font-medium text-slate-700 dark:text-slate-300 mb-1"
            >
              {{ t('TASKS.RECURRENCE_LABEL') }}
            </label>
            <select
              v-model="recurrenceInterval"
              class="w-full px-3 py-2 text-sm border border-slate-200 dark:border-slate-600 rounded-lg bg-white dark:bg-slate-700 text-slate-800 dark:text-slate-100 focus:outline-none focus:ring-2 focus:ring-woot-500"
            >
              <option value="">
                {{ t('TASKS.RECURRENCE_OPTIONS.NONE') }}
              </option>
              <option value="daily">
                {{ t('TASKS.RECURRENCE_OPTIONS.DAILY') }}
              </option>
              <option value="weekly">
                {{ t('TASKS.RECURRENCE_OPTIONS.WEEKLY') }}
              </option>
              <option value="monthly">
                {{ t('TASKS.RECURRENCE_OPTIONS.MONTHLY') }}
              </option>
            </select>
          </div>
        </div>

        <div
          class="flex items-center justify-end gap-2 px-6 py-4 border-t border-slate-100 dark:border-slate-700"
        >
          <button
            class="px-4 py-2 text-sm text-slate-600 dark:text-slate-400 hover:bg-slate-100 dark:hover:bg-slate-700 rounded-lg transition-colors"
            @click="emit('close')"
          >
            {{ t('TASKS.CANCEL') }}
          </button>
          <button
            class="px-4 py-2 text-sm font-medium text-white bg-woot-500 hover:bg-woot-600 rounded-lg transition-colors disabled:opacity-50 flex items-center gap-2"
            :disabled="!isFormValid || isSubmitting"
            @click="handleSubmit"
          >
            <span
              v-if="isSubmitting"
              class="i-lucide-loader size-4 animate-spin"
            />
            {{ t(isEditMode ? 'TASKS.SAVE' : 'TASKS.CREATE') }}
          </button>
        </div>
      </div>
    </div>
  </Teleport>
</template>
