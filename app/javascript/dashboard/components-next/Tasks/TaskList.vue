<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import TaskItem from './TaskItem.vue';
import TaskFormModal from './TaskFormModal.vue';

const props = defineProps({
  contactId: { type: Number, required: true },
  conversationId: { type: [Number, String], default: null },
  pipelineItemId: { type: [Number, String], default: null },
});

const { t } = useI18n();
const store = useStore();
const isFetching = ref(true);
const showFormModal = ref(false);
const editingTask = ref(null);

const openCreateModal = () => {
  editingTask.value = null;
  showFormModal.value = true;
};

const openEditModal = task => {
  editingTask.value = task;
  showFormModal.value = true;
};

const closeFormModal = () => {
  showFormModal.value = false;
  editingTask.value = null;
};

// contactId/conversationId/pipelineItemId are set once by the parent and don't change for
// the lifetime of this instance, so these don't need to be reactive - and useMapGetter
// doesn't unref its key argument, so a computed getter name wouldn't work here anyway.
const resolveContext = () => {
  if (props.pipelineItemId) {
    return {
      fetchAction: 'tasks/fetchForPipelineItem',
      getterName: 'tasks/getTasksForPipelineItem',
      fetchId: props.pipelineItemId,
    };
  }
  if (props.conversationId) {
    return {
      fetchAction: 'tasks/fetchForConversation',
      getterName: 'tasks/getTasksForConversation',
      fetchId: props.conversationId,
    };
  }
  return {
    fetchAction: 'tasks/fetchForContact',
    getterName: 'tasks/getTasksForContact',
    fetchId: props.contactId,
  };
};
const { fetchAction, getterName, fetchId } = resolveContext();

const tasksGetter = useMapGetter(getterName);
const tasks = computed(() =>
  [...tasksGetter.value(Number(fetchId))].sort(
    (a, b) => a.due_date - b.due_date
  )
);

onMounted(async () => {
  try {
    await store.dispatch(fetchAction, fetchId);
  } finally {
    isFetching.value = false;
  }
});
</script>

<template>
  <div class="px-4 py-3">
    <div v-if="isFetching" class="flex justify-center py-4">
      <span class="i-lucide-loader size-5 animate-spin text-slate-400" />
    </div>
    <template v-else>
      <div v-if="!tasks.length" class="text-center py-3">
        <p class="text-sm text-n-slate-11 mb-3">
          {{ t('TASKS.EMPTY_STATE') }}
        </p>
        <button
          class="px-3 py-1.5 text-sm font-medium text-white bg-woot-500 hover:bg-woot-600 rounded-lg transition-colors"
          @click="openCreateModal"
        >
          {{ t('TASKS.CREATE') }}
        </button>
      </div>
      <div v-else class="space-y-2">
        <TaskItem
          v-for="task in tasks"
          :key="task.id"
          :task="task"
          @edit="openEditModal"
        />
        <button
          class="text-sm text-woot-500 hover:text-woot-600 font-medium transition-colors"
          @click="openCreateModal"
        >
          + {{ t('TASKS.CREATE') }}
        </button>
      </div>
    </template>

    <TaskFormModal
      v-if="showFormModal"
      :contact-id="contactId"
      :conversation-id="conversationId"
      :pipeline-item-id="pipelineItemId"
      :task="editingTask"
      @close="closeFormModal"
    />
  </div>
</template>
