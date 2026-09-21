<script setup>
import { computed, inject } from 'vue';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import {
  dynamicTime,
  shortTimestamp,
  dateFormat,
} from 'shared/helpers/timeHelper';
import { useNumberFormatter } from 'shared/composables/useNumberFormatter';
import KanbanRunMacroMenu from './KanbanRunMacroMenu.vue';

const props = defineProps({
  item: { type: Object, required: true },
});

const emit = defineEmits(['click', 'export']);
const { t } = useI18n();

const route = useRoute();
const accountId = computed(() => route.params.accountId);
const { formatCurrency } = useNumberFormatter();

const formattedValue = computed(() => {
  if (!props.item.value || Number(props.item.value) === 0) return null;
  return formatCurrency(props.item.value);
});

// Same for every card on the board - computed once in KanbanBoard.vue and provided down
// instead of recomputed per card instance (task 09). The default (a factory, so it's only built
// when nothing was provided) exists just for a card rendered outside the board.
const visibleCardAttributeDefinitions = inject(
  'kanbanCardAttributeDefinitions',
  () => computed(() => []),
  true
);

const createdAtShort = computed(() =>
  props.item.created_at
    ? shortTimestamp(dynamicTime(props.item.created_at))
    : null
);
const updatedAtShort = computed(() =>
  props.item.updated_at
    ? shortTimestamp(dynamicTime(props.item.updated_at))
    : null
);
const datesTooltip = computed(() => {
  const created = props.item.created_at
    ? dateFormat(props.item.created_at, 'MMM d, yyyy HH:mm')
    : '—';
  const updated = props.item.updated_at
    ? dateFormat(props.item.updated_at, 'MMM d, yyyy HH:mm')
    : '—';
  return `${t('KANBAN.ITEM.CREATED_AT')}: ${created} · ${t('KANBAN.ITEM.UPDATED_AT')}: ${updated}`;
});

const visibleAttributes = computed(() =>
  visibleCardAttributeDefinitions.value
    .map(attr => ({
      key: attr.attribute_key,
      label: attr.attribute_display_name,
      value: props.item.custom_attributes?.[attr.attribute_key],
    }))
    .filter(
      attr =>
        attr.value !== undefined && attr.value !== null && attr.value !== ''
    )
);
</script>

<template>
  <div
    class="group bg-white dark:bg-slate-700 rounded-lg p-3 shadow-sm cursor-pointer hover:shadow-md transition-shadow border border-slate-100 dark:border-slate-600 relative"
    @click="emit('click', item)"
  >
    <div
      class="absolute top-2 right-2 flex items-center gap-1 opacity-0 group-hover:opacity-100 transition-opacity"
    >
      <KanbanRunMacroMenu
        :pipeline-item-ids="[item.id]"
        button-class="p-0.5 text-slate-400 hover:text-woot-500"
      />
      <button
        v-tooltip.top="t('KANBAN.ITEM.EXPORT.BUTTON')"
        class="p-0.5 text-slate-400 hover:text-woot-500"
        @click.stop="emit('export', item)"
      >
        <span class="i-lucide-arrow-right-left size-3.5" />
      </button>
    </div>
    <router-link
      v-if="item.contact?.id"
      :to="{
        name: 'contacts_edit',
        params: { accountId: accountId, contactId: item.contact.id },
      }"
      class="flex items-center gap-2 mb-1.5 hover:underline"
      @click.stop
    >
      <img
        v-if="item.contact?.avatar_url"
        :src="item.contact.avatar_url"
        :alt="item.contact?.name"
        class="w-6 h-6 rounded-full flex-shrink-0 object-cover"
      />
      <span
        v-else
        class="w-6 h-6 rounded-full flex-shrink-0 bg-woot-100 dark:bg-woot-900 flex items-center justify-center text-xs font-semibold text-woot-600 dark:text-woot-300"
      >
        {{ item.contact?.name?.[0]?.toUpperCase() || '?' }}
      </span>
      <span
        class="text-sm font-medium text-slate-700 dark:text-slate-200 truncate"
      >
        {{ item.title || item.contact?.name }}
      </span>
    </router-link>
    <div v-else class="flex items-center gap-2 mb-1.5">
      <span
        class="w-6 h-6 rounded-full flex-shrink-0 bg-woot-100 dark:bg-woot-900 flex items-center justify-center text-xs font-semibold text-woot-600 dark:text-woot-300"
      >
        ?
      </span>
      <span
        class="text-sm font-medium text-slate-700 dark:text-slate-200 truncate"
      >
        {{ item.title }}
      </span>
    </div>

    <div
      v-if="item.contact?.email"
      class="text-xs text-slate-400 dark:text-slate-500 truncate mb-1"
    >
      {{ item.contact.email }}
    </div>

    <div v-if="item.label_list?.length" class="flex flex-wrap gap-1 mt-1.5">
      <span
        v-for="label in item.label_list"
        :key="label"
        class="px-1.5 py-0.5 rounded text-[10px] font-medium bg-slate-100 dark:bg-slate-600 text-slate-600 dark:text-slate-200"
      >
        {{ label }}
      </span>
    </div>

    <div v-if="visibleAttributes.length" class="flex flex-col gap-0.5 mt-1.5">
      <div
        v-for="attr in visibleAttributes"
        :key="attr.key"
        class="text-[10px] text-slate-500 dark:text-slate-400 truncate"
      >
        <span class="font-medium">{{ attr.label }}:</span> {{ attr.value }}
      </div>
    </div>

    <div class="flex items-center justify-between mt-2">
      <span
        v-if="formattedValue"
        class="text-xs font-semibold text-emerald-600 dark:text-emerald-400"
      >
        {{ formattedValue }}
      </span>
      <span
        v-if="item.overdue_tasks_count > 0"
        v-tooltip.top="
          t('KANBAN.ITEM.OVERDUE_TASKS_TOOLTIP', {
            count: item.overdue_tasks_count,
          })
        "
        class="flex items-center gap-0.5 px-1.5 py-0.5 rounded text-[10px] font-medium bg-red-100 dark:bg-red-800 text-red-600 dark:text-red-300"
      >
        <span class="i-lucide-alert-triangle size-2.5" />
        {{ item.overdue_tasks_count }}
      </span>
      <span
        v-if="item.conversation_id"
        class="text-xs text-woot-500 dark:text-woot-400 ml-auto"
      >
        #{{ item.conversation_id }}
      </span>
      <img
        v-if="item.assignee?.thumbnail"
        :src="item.assignee.thumbnail"
        :title="item.assignee.name"
        class="w-5 h-5 rounded-full object-cover ml-auto flex-shrink-0"
      />
      <span
        v-else-if="item.assignee"
        :title="item.assignee.name"
        class="w-5 h-5 rounded-full bg-slate-200 dark:bg-slate-600 flex items-center justify-center text-[10px] font-semibold text-slate-600 dark:text-slate-200 ml-auto flex-shrink-0"
      >
        {{ item.assignee.name?.[0]?.toUpperCase() }}
      </span>
    </div>

    <div
      v-if="createdAtShort || updatedAtShort"
      v-tooltip.top="datesTooltip"
      class="flex items-center gap-1.5 mt-1.5 text-[10px] text-slate-500 dark:text-slate-400 cursor-default"
    >
      <span
        class="i-lucide-plus-circle size-3 text-slate-500 dark:text-slate-400 flex-shrink-0"
      />
      <span>{{ createdAtShort }}</span>
      <span
        class="i-lucide-pencil size-3 text-slate-500 dark:text-slate-400 flex-shrink-0 ml-1"
      />
      <span>{{ updatedAtShort }}</span>
    </div>
  </div>
</template>
