<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAdmin } from 'dashboard/composables/useAdmin';
import { dateFormat } from 'shared/helpers/timeHelper';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';

const props = defineProps({
  task: { type: Object, required: true },
});

const emit = defineEmits(['edit']);

const { t } = useI18n();
const store = useStore();
const { isAdmin } = useAdmin();
const currentUser = useMapGetter('getCurrentUser');

const isCompleted = computed(() => !!props.task.completed_at);
const isOverdue = computed(
  () => !isCompleted.value && props.task.due_date * 1000 < Date.now()
);
const formattedDueDate = computed(() =>
  dateFormat(props.task.due_date, 'MMM d, yyyy HH:mm')
);
const canDelete = computed(
  () => isAdmin.value || currentUser.value?.id === props.task.assignee?.id
);

const handleComplete = () => {
  if (isCompleted.value) return;
  store.dispatch('tasks/complete', props.task.id);
};

const handleDelete = () => {
  store.dispatch('tasks/delete', props.task.id);
};

const handleEdit = () => {
  emit('edit', props.task);
};
</script>

<template>
  <div
    class="flex items-start gap-2 p-2 rounded-lg border border-n-weak hover:bg-n-alpha-1 transition-colors"
  >
    <input
      type="checkbox"
      class="mt-0.5 rounded border-slate-300 dark:border-slate-600 text-woot-500 focus:ring-woot-500"
      :checked="isCompleted"
      :disabled="isCompleted"
      @change="handleComplete"
    />
    <div class="min-w-0 flex-1">
      <p
        class="text-sm font-medium text-n-slate-12 truncate"
        :class="{ 'line-through text-n-slate-11': isCompleted }"
      >
        {{ task.title }}
      </p>
      <div class="flex items-center gap-1.5 mt-0.5">
        <span
          class="text-xs"
          :class="isOverdue ? 'text-n-ruby-11 font-medium' : 'text-n-slate-11'"
        >
          {{ formattedDueDate }}
        </span>
        <span
          v-if="isOverdue"
          class="text-xs font-medium text-n-ruby-11 px-1.5 py-0.5 rounded bg-n-ruby-3"
        >
          {{ t('TASKS.OVERDUE') }}
        </span>
      </div>
    </div>
    <Avatar
      v-if="task.assignee"
      :src="task.assignee.avatar_url"
      :name="task.assignee.name"
      :size="20"
    />
    <button
      class="text-n-slate-10 hover:text-n-slate-12 transition-colors"
      @click="handleEdit"
    >
      <span class="i-lucide-pencil size-4" />
    </button>
    <button
      v-if="canDelete"
      class="text-n-slate-10 hover:text-n-ruby-11 transition-colors"
      @click="handleDelete"
    >
      <span class="i-lucide-trash-2 size-4" />
    </button>
  </div>
</template>
