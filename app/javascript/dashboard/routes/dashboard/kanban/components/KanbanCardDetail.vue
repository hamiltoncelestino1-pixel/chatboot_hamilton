<script setup>
import { ref, computed, watch, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { frontendURL, conversationUrl } from 'dashboard/helper/URLHelper';
import MultiselectDropdown from 'shared/components/ui/MultiselectDropdown.vue';
import TagInput from 'dashboard/components-next/taginput/TagInput.vue';
import PipelineItemLabels from './PipelineItemLabels.vue';
import AccordionItem from 'dashboard/components/Accordion/AccordionItem.vue';
import KanbanRunMacroMenu from './KanbanRunMacroMenu.vue';
import ButtonV4 from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  item: { type: Object, default: null },
});

const emit = defineEmits(['close', 'export']);

const { t } = useI18n();
const store = useStore();
const route = useRoute();
const router = useRouter();
const activePipeline = useMapGetter('kanban/getActivePipeline');
const getStagesForPipeline = useMapGetter('kanban/getStagesForPipeline');
const getPipelineMembers = useMapGetter('pipelineMembers/getPipelineMembers');
const uiFlags = useMapGetter('kanban/getUIFlags');
const teams = useMapGetter('teams/getTeams');

const stages = computed(() =>
  activePipeline.value
    ? getStagesForPipeline.value(activePipeline.value.id)
    : []
);

const assignableAgents = computed(() => {
  const noneOption = {
    id: null,
    name: t('KANBAN.ITEM.ASSIGNEE_NONE'),
    thumbnail: '',
  };
  if (!activePipeline.value) return [noneOption];
  return [noneOption, ...getPipelineMembers.value(activePipeline.value.id)];
});

const assignableTeams = computed(() => {
  const noneOption = { id: null, name: t('KANBAN.ITEM.TEAM_NONE') };
  return [noneOption, ...teams.value];
});

const form = ref({ title: '', value: '', notes: '', pipeline_stage_id: null });
const assignee = ref(null);
const team = ref(null);
const customAttributeValues = ref({});
const isAttributesOpen = ref(false);

const pipelineItemAttributes = computed(() =>
  store.getters['attributes/getAttributesByModel']('pipeline_item_attribute')
);

// Conversation linking
const contactConversationsGetter = useMapGetter(
  'contactConversations/getContactConversation'
);
const contactConversations = computed(() =>
  props.item?.contact
    ? contactConversationsGetter.value(props.item.contact.id)
    : []
);

const inboxGetter = useMapGetter('inboxes/getInbox');

const conversationMenuItems = computed(() =>
  contactConversations.value.map(c => ({
    label: `#${c.id}${inboxGetter.value(c.inbox_id)?.name ? ` · ${inboxGetter.value(c.inbox_id).name}` : ''}`,
    value: c.id,
    action: 'select',
  }))
);

const onSelectConversation = async ({ value }) => {
  await store.dispatch('kanban/updateItem', {
    id: props.item.id,
    conversation_id: value,
  });
};

const clearConversation = async () => {
  await store.dispatch('kanban/updateItem', {
    id: props.item.id,
    conversation_id: null,
  });
};

const linkedConversationUrl = computed(() => {
  if (!props.item?.conversation_id) return null;
  return frontendURL(
    conversationUrl({
      accountId: route.params.accountId,
      id: props.item.conversation_id,
    })
  );
});

const openLinkedConversation = e => {
  if (e.metaKey || e.ctrlKey) {
    e.preventDefault();
    window.open(
      `${window.chatwootConfig.hostURL}${linkedConversationUrl.value}`,
      '_blank',
      'noopener,noreferrer'
    );
    return;
  }
  router.push({ path: linkedConversationUrl.value });
};

// Re-initialize form only when a different card is opened (identity change)
watch(
  () => props.item?.id,
  (newId, oldId) => {
    if (newId && newId !== oldId) {
      const item = props.item;
      form.value = {
        title: item.title || '',
        value: item.value || '',
        notes: item.notes || '',
        pipeline_stage_id: item.pipeline_stage_id,
      };
      customAttributeValues.value = { ...(item.custom_attributes || {}) };
    }
  },
  { immediate: true }
);

// Sync assignee/team from server without overwriting unrelated form fields
watch(
  () => props.item?.assignee,
  val => {
    assignee.value = val || null;
  },
  { immediate: true }
);
watch(
  () => props.item?.team,
  val => {
    team.value = val || null;
  },
  { immediate: true }
);

watch(
  () => props.item?.contact?.id,
  contactId => {
    if (contactId) store.dispatch('contactConversations/get', contactId);
  },
  { immediate: true }
);

watch(
  activePipeline,
  pipeline => {
    if (pipeline) {
      store.dispatch('pipelineMembers/get', { pipelineId: pipeline.id });
    }
  },
  { immediate: true }
);

onMounted(() => {
  store.dispatch('teams/get');
  store.dispatch('labels/get');
  store.dispatch('attributes/get');
});

const handleCustomAttributeChange = async (key, value) => {
  customAttributeValues.value[key] = value;
  await store.dispatch('kanban/updateItem', {
    id: props.item.id,
    custom_attributes: { ...customAttributeValues.value },
  });
};

const onAssignAgent = async selected => {
  const assigneeId = selected?.id || null;
  try {
    await store.dispatch('kanban/updateItem', {
      id: props.item.id,
      assignee_id: assigneeId,
    });
    assignee.value = assigneeId ? selected : null;
  } catch {
    useAlert(t('KANBAN.ITEM.ERRORS.ASSIGNEE_NOT_MEMBER'));
  }
};

const onAssignTeam = async selected => {
  const teamId = selected?.id || null;
  await store.dispatch('kanban/updateItem', {
    id: props.item.id,
    team_id: teamId,
  });
  team.value = teamId ? selected : null;
};

const handleSave = async () => {
  try {
    const payload = {
      id: props.item.id,
      title: form.value.title,
      value: form.value.value,
      notes: form.value.notes,
    };

    if (form.value.pipeline_stage_id !== props.item.pipeline_stage_id) {
      await store.dispatch('kanban/moveItem', {
        itemId: props.item.id,
        fromStageId: props.item.pipeline_stage_id,
        toStageId: form.value.pipeline_stage_id,
        position: 0,
      });
    }

    await store.dispatch('kanban/updateItem', payload);
    useAlert(t('KANBAN.ITEM.API.UPDATE_SUCCESS'));
    emit('close');
  } catch {
    useAlert(t('KANBAN.ITEM.API.ERROR'));
  }
};

const handleDelete = async () => {
  try {
    await store.dispatch('kanban/deleteItem', props.item.id);
    useAlert(t('KANBAN.ITEM.API.DELETE_SUCCESS'));
    emit('close');
  } catch {
    useAlert(t('KANBAN.ITEM.API.ERROR'));
  }
};
</script>

<template>
  <Teleport to="body">
    <div
      v-if="item"
      class="fixed inset-0 z-50 flex"
      @click.self="emit('close')"
    >
      <div class="fixed inset-0 bg-black/30" @click="emit('close')" />

      <div
        class="ml-auto relative w-full max-w-md h-full bg-white dark:bg-slate-800 shadow-xl flex flex-col z-10"
      >
        <div
          class="flex items-center justify-between px-5 py-4 border-b border-slate-100 dark:border-slate-700"
        >
          <h3
            class="text-base font-semibold text-slate-800 dark:text-slate-100"
          >
            {{ t('KANBAN.ITEM.EDIT') }}
          </h3>
          <button
            class="text-slate-400 hover:text-slate-600 dark:hover:text-slate-200 transition-colors"
            @click="emit('close')"
          >
            <span class="i-lucide-x size-5" />
          </button>
        </div>

        <div class="flex-1 overflow-y-auto px-5 py-4 space-y-4">
          <div
            v-if="item.contact"
            class="p-3 bg-slate-50 dark:bg-slate-700/50 rounded-lg"
          >
            <div class="flex items-center gap-3">
              <img
                v-if="item.contact.avatar_url"
                :src="item.contact.avatar_url"
                class="w-10 h-10 rounded-full object-cover flex-shrink-0"
              />
              <div
                v-else
                class="w-10 h-10 rounded-full bg-woot-100 dark:bg-woot-900 flex items-center justify-center text-sm font-bold text-woot-600 dark:text-woot-300 flex-shrink-0"
              >
                {{ item.contact.name?.[0]?.toUpperCase() || '?' }}
              </div>
              <div class="min-w-0 flex-1">
                <p
                  class="text-sm font-semibold text-slate-800 dark:text-slate-100 truncate"
                >
                  {{ item.contact.name }}
                </p>
                <p
                  v-if="item.contact.email"
                  class="text-xs text-slate-500 dark:text-slate-400 truncate"
                >
                  {{ item.contact.email }}
                </p>
                <p
                  v-if="item.contact.phone_number"
                  class="text-xs text-slate-500 dark:text-slate-400"
                >
                  {{ item.contact.phone_number }}
                </p>
              </div>
              <div class="flex items-center gap-1 flex-shrink-0">
                <router-link
                  :to="{
                    name: 'contacts_edit',
                    params: { contactId: item.contact.id },
                  }"
                  class="p-1 text-slate-400 hover:text-woot-500 transition-colors"
                  :title="t('KANBAN.ITEM.CONTACT.VIEW_PROFILE')"
                >
                  <span class="i-lucide-external-link size-4" />
                </router-link>
              </div>
            </div>
          </div>

          <div
            v-if="item.contact"
            class="p-3 bg-woot-50 dark:bg-woot-900/20 rounded-lg"
          >
            <p
              class="text-xs font-medium text-woot-700 dark:text-woot-300 mb-1.5"
            >
              {{ t('KANBAN.ITEM.LINKED_CONVERSATION') }}
            </p>
            <div
              v-if="item.conversation_id"
              class="flex items-center justify-between gap-2"
            >
              <span class="text-sm text-woot-700 dark:text-woot-300 truncate">
                #{{ item.conversation_id }}
              </span>
              <div class="flex items-center gap-1 flex-shrink-0">
                <ButtonV4
                  size="xs"
                  faded
                  icon="i-lucide-external-link"
                  :label="t('KANBAN.ITEM.CONVERSATION.VIEW')"
                  @click="openLinkedConversation"
                />
                <button
                  class="p-1 text-slate-400 hover:text-red-500 transition-colors"
                  :title="t('KANBAN.ITEM.CONVERSATION.CLEAR')"
                  @click="clearConversation"
                >
                  <span class="i-lucide-x size-4" />
                </button>
              </div>
            </div>
            <TagInput
              v-else
              mode="single"
              :placeholder="t('KANBAN.ITEM.CONVERSATION.SEARCH_PLACEHOLDER')"
              :menu-items="conversationMenuItems"
              show-dropdown
              :auto-open-dropdown="false"
              @add="onSelectConversation"
            />
          </div>

          <div>
            <label
              class="block text-xs font-medium text-slate-600 dark:text-slate-400 mb-1"
            >
              {{ t('KANBAN.ITEM.ASSIGNEE_LABEL') }}
            </label>
            <MultiselectDropdown
              :options="assignableAgents"
              :selected-item="assignee"
              :multiselector-title="t('AGENT_MGMT.MULTI_SELECTOR.TITLE.AGENT')"
              :multiselector-placeholder="t('KANBAN.ITEM.ASSIGNEE_PLACEHOLDER')"
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
              class="block text-xs font-medium text-slate-600 dark:text-slate-400 mb-1"
            >
              {{ t('KANBAN.ITEM.TEAM_LABEL') }}
            </label>
            <MultiselectDropdown
              :options="assignableTeams"
              :selected-item="team"
              :multiselector-title="t('AGENT_MGMT.MULTI_SELECTOR.TITLE.TEAM')"
              :multiselector-placeholder="t('KANBAN.ITEM.TEAM_PLACEHOLDER')"
              :no-search-result="
                t('AGENT_MGMT.MULTI_SELECTOR.SEARCH.NO_RESULTS.TEAM')
              "
              :input-placeholder="
                t('AGENT_MGMT.MULTI_SELECTOR.SEARCH.PLACEHOLDER.TEAM')
              "
              @select="onAssignTeam"
            />
          </div>

          <div>
            <label
              class="block text-xs font-medium text-slate-600 dark:text-slate-400 mb-1"
            >
              {{ t('KANBAN.ITEM.LABELS_TITLE') }}
            </label>
            <PipelineItemLabels :item="item" />
          </div>

          <AccordionItem
            v-if="pipelineItemAttributes.length"
            :title="t('KANBAN.ITEM.CUSTOM_ATTRIBUTES_TITLE')"
            :is-open="isAttributesOpen"
            compact
            @toggle="isAttributesOpen = !isAttributesOpen"
          >
            <div class="space-y-3 p-3">
              <div v-for="attr in pipelineItemAttributes" :key="attr.id">
                <label
                  class="block text-xs text-slate-500 dark:text-slate-400 mb-1"
                >
                  {{ attr.attribute_display_name }}
                </label>
                <input
                  v-if="['text', 'link'].includes(attr.attribute_display_type)"
                  :value="customAttributeValues[attr.attribute_key]"
                  type="text"
                  class="w-full px-3 py-2 text-sm border border-slate-200 dark:border-slate-600 rounded-lg bg-white dark:bg-slate-700 text-slate-800 dark:text-slate-100 focus:outline-none focus:ring-2 focus:ring-woot-500"
                  @change="
                    handleCustomAttributeChange(
                      attr.attribute_key,
                      $event.target.value
                    )
                  "
                />
                <input
                  v-else-if="
                    ['number', 'currency', 'percent'].includes(
                      attr.attribute_display_type
                    )
                  "
                  :value="customAttributeValues[attr.attribute_key]"
                  type="number"
                  class="w-full px-3 py-2 text-sm border border-slate-200 dark:border-slate-600 rounded-lg bg-white dark:bg-slate-700 text-slate-800 dark:text-slate-100 focus:outline-none focus:ring-2 focus:ring-woot-500"
                  @change="
                    handleCustomAttributeChange(
                      attr.attribute_key,
                      $event.target.value
                    )
                  "
                />
                <input
                  v-else-if="attr.attribute_display_type === 'date'"
                  :value="customAttributeValues[attr.attribute_key]"
                  type="date"
                  class="w-full px-3 py-2 text-sm border border-slate-200 dark:border-slate-600 rounded-lg bg-white dark:bg-slate-700 text-slate-800 dark:text-slate-100 focus:outline-none focus:ring-2 focus:ring-woot-500"
                  @change="
                    handleCustomAttributeChange(
                      attr.attribute_key,
                      $event.target.value
                    )
                  "
                />
                <input
                  v-else-if="attr.attribute_display_type === 'checkbox'"
                  :checked="customAttributeValues[attr.attribute_key]"
                  type="checkbox"
                  class="w-4 h-4 rounded border-slate-300 text-woot-500 focus:ring-woot-500"
                  @change="
                    handleCustomAttributeChange(
                      attr.attribute_key,
                      $event.target.checked
                    )
                  "
                />
                <select
                  v-else-if="attr.attribute_display_type === 'list'"
                  :value="customAttributeValues[attr.attribute_key]"
                  class="w-full px-3 py-2 text-sm border border-slate-200 dark:border-slate-600 rounded-lg bg-white dark:bg-slate-700 text-slate-800 dark:text-slate-100 focus:outline-none focus:ring-2 focus:ring-woot-500"
                  @change="
                    handleCustomAttributeChange(
                      attr.attribute_key,
                      $event.target.value
                    )
                  "
                >
                  <option value="">—</option>
                  <option
                    v-for="val in attr.attribute_values"
                    :key="val"
                    :value="val"
                  >
                    {{ val }}
                  </option>
                </select>
              </div>
            </div>
          </AccordionItem>

          <div>
            <label
              class="block text-xs font-medium text-slate-600 dark:text-slate-400 mb-1"
            >
              {{ t('KANBAN.ITEM.TITLE_LABEL') }}
            </label>
            <input
              v-model="form.title"
              type="text"
              class="w-full px-3 py-2 text-sm border border-slate-200 dark:border-slate-600 rounded-lg bg-white dark:bg-slate-700 text-slate-800 dark:text-slate-100 focus:outline-none focus:ring-2 focus:ring-woot-500"
              :placeholder="t('KANBAN.ITEM.TITLE_PLACEHOLDER')"
            />
          </div>

          <div>
            <label
              class="block text-xs font-medium text-slate-600 dark:text-slate-400 mb-1"
            >
              {{ t('KANBAN.ITEM.VALUE_LABEL') }}
            </label>
            <input
              v-model="form.value"
              type="number"
              step="0.01"
              min="0"
              class="w-full px-3 py-2 text-sm border border-slate-200 dark:border-slate-600 rounded-lg bg-white dark:bg-slate-700 text-slate-800 dark:text-slate-100 focus:outline-none focus:ring-2 focus:ring-woot-500"
              :placeholder="t('KANBAN.ITEM.VALUE_PLACEHOLDER')"
            />
          </div>

          <div>
            <label
              class="block text-xs font-medium text-slate-600 dark:text-slate-400 mb-1"
            >
              {{ t('KANBAN.STAGE.NAME_LABEL') }}
            </label>
            <select
              v-model="form.pipeline_stage_id"
              class="w-full px-3 py-2 text-sm border border-slate-200 dark:border-slate-600 rounded-lg bg-white dark:bg-slate-700 text-slate-800 dark:text-slate-100 focus:outline-none focus:ring-2 focus:ring-woot-500"
            >
              <option v-for="stage in stages" :key="stage.id" :value="stage.id">
                {{ stage.name }}
              </option>
            </select>
          </div>

          <div>
            <label
              class="block text-xs font-medium text-slate-600 dark:text-slate-400 mb-1"
            >
              {{ t('KANBAN.ITEM.NOTES_LABEL') }}
            </label>
            <textarea
              v-model="form.notes"
              rows="4"
              class="w-full px-3 py-2 text-sm border border-slate-200 dark:border-slate-600 rounded-lg bg-white dark:bg-slate-700 text-slate-800 dark:text-slate-100 focus:outline-none focus:ring-2 focus:ring-woot-500 resize-none"
              :placeholder="t('KANBAN.ITEM.NOTES_PLACEHOLDER')"
            />
          </div>
        </div>

        <div
          class="flex items-center justify-between px-5 py-4 border-t border-slate-100 dark:border-slate-700 flex-wrap gap-2"
        >
          <div class="flex items-center gap-1">
            <button
              v-tooltip="t('KANBAN.ITEM.DELETE')"
              class="p-2 text-red-600 dark:text-red-400 hover:bg-red-50 dark:hover:bg-red-900/20 rounded-lg transition-colors"
              :disabled="uiFlags.isDeleting"
              @click="handleDelete"
            >
              <span class="i-lucide-trash-2 size-4" />
            </button>
            <button
              v-tooltip="t('KANBAN.ITEM.EXPORT.BUTTON')"
              class="p-2 text-slate-600 dark:text-slate-400 hover:bg-slate-100 dark:hover:bg-slate-700 rounded-lg transition-colors"
              @click="emit('export', item)"
            >
              <span class="i-lucide-arrow-right-left size-4" />
            </button>
            <KanbanRunMacroMenu
              :pipeline-item-ids="[item.id]"
              open-upward
              button-class="p-2 text-slate-600 dark:text-slate-400 hover:bg-slate-100 dark:hover:bg-slate-700 rounded-lg transition-colors"
            />
          </div>

          <div class="flex gap-2">
            <button
              class="px-4 py-2 text-sm text-slate-600 dark:text-slate-400 hover:bg-slate-100 dark:hover:bg-slate-700 rounded-lg transition-colors"
              @click="emit('close')"
            >
              {{ t('KANBAN.ITEM.CANCEL') }}
            </button>
            <button
              class="px-4 py-2 text-sm font-medium text-white bg-woot-500 hover:bg-woot-600 rounded-lg transition-colors disabled:opacity-50"
              :disabled="uiFlags.isUpdating"
              @click="handleSave"
            >
              {{ t('KANBAN.ITEM.SAVE') }}
            </button>
          </div>
        </div>
      </div>
    </div>
  </Teleport>
</template>
