<script setup>
import { ref, reactive, computed, watch, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import ContactSelector from 'dashboard/components-next/NewConversation/components/ContactSelector.vue';
import {
  createContactSearcher,
  createNewContact,
} from 'dashboard/components-next/NewConversation/helpers/composeConversationHelper';

const props = defineProps({
  stageId: { type: Number, default: null },
  contactId: { type: Number, default: null },
  conversationId: { type: Number, default: null },
  pipelineId: { type: Number, default: null },
});

const emit = defineEmits(['close', 'created']);

const { t } = useI18n();
const store = useStore();
const uiFlags = useMapGetter('kanban/getUIFlags');
const activePipeline = useMapGetter('kanban/getActivePipeline');
const getStagesForPipeline = useMapGetter('kanban/getStagesForPipeline');
const pipelines = useMapGetter('kanban/getPipelines');
const currentUser = useMapGetter('getCurrentUser');
const preselectedContact = useMapGetter('contacts/getContactById');

const selectedContact = ref(null);
const contacts = ref([]);
const showContactsDropdown = ref(false);
const isCreatingContact = ref(false);

const contactForDisplay = computed(() =>
  props.contactId
    ? preselectedContact.value(props.contactId)
    : selectedContact.value
);

const searchContactsFn = createContactSearcher();

const selectedPipelineId = ref(
  props.pipelineId || activePipeline.value?.id || null
);

const stages = computed(() => {
  const pipelineId =
    props.pipelineId || selectedPipelineId.value || activePipeline.value?.id;
  return pipelineId ? getStagesForPipeline.value(pipelineId) : [];
});

const form = reactive({
  title: '',
  value: '',
  pipeline_stage_id: props.stageId || null,
});

watch(
  stages,
  newStages => {
    if (!form.pipeline_stage_id && newStages.length) {
      const startStage = newStages.find(s => s.stage_type === 'start');
      form.pipeline_stage_id =
        props.stageId || startStage?.id || newStages[0]?.id;
    }
  },
  { immediate: true }
);
const isSearching = ref(false);
const assignToMe = ref(false);

const handleSearchContacts = async query => {
  showContactsDropdown.value = true;
  isSearching.value = true;
  contacts.value = await searchContactsFn(query);
  isSearching.value = false;
};

const handleSetSelectedContact = async ({ value, action, ...rest }) => {
  if (action === 'create') {
    isCreatingContact.value = true;
    try {
      selectedContact.value = await createNewContact(value);
    } catch {
      useAlert(t('KANBAN.ITEM.CONTACT_SELECTOR.CREATE_ERROR'));
      return;
    } finally {
      isCreatingContact.value = false;
    }
  } else {
    selectedContact.value = rest;
  }
  contacts.value = [];
  showContactsDropdown.value = false;
};

const clearSelectedContact = () => {
  selectedContact.value = null;
};

const showPipelineSelector = computed(
  () => !!props.contactId || (!props.pipelineId && !activePipeline.value)
);

onMounted(async () => {
  if (props.contactId && !preselectedContact.value(props.contactId)) {
    store.dispatch('contacts/show', { id: props.contactId });
  }
  if (props.contactId || (!props.pipelineId && !activePipeline.value)) {
    await store.dispatch('kanban/fetchPipelines');
    if (!selectedPipelineId.value && pipelines.value.length) {
      selectedPipelineId.value = pipelines.value[0].id;
    }
  }
});

const handleSubmit = async () => {
  const contactIdToUse = props.contactId || selectedContact.value?.id;
  if (!contactIdToUse) return;
  try {
    const item = await store.dispatch('kanban/createItem', {
      contact_id: contactIdToUse,
      conversation_id: props.conversationId || null,
      pipeline_stage_id: form.pipeline_stage_id,
      title: form.title || null,
      value: form.value || null,
      assignee_id: assignToMe.value ? currentUser.value.id : null,
    });
    useAlert(t('KANBAN.ITEM.API.CREATE_SUCCESS'));
    emit('created', item);
    emit('close');
  } catch (error) {
    useAlert(error.message || t('KANBAN.ITEM.API.ERROR'));
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
            {{ t('KANBAN.ITEM.ADD') }}
          </h3>
          <button
            class="text-slate-400 hover:text-slate-600 dark:hover:text-slate-200 transition-colors"
            @click="emit('close')"
          >
            <span class="i-lucide-x size-5" />
          </button>
        </div>

        <div class="px-6 py-4 space-y-4">
          <!-- Contact: read-only when pre-filled, search when not -->
          <div>
            <label
              class="block text-sm font-medium text-slate-700 dark:text-slate-300 mb-1"
            >
              {{ t('KANBAN.ITEM.CONTACT_LABEL') }}
              <span class="text-red-500">*</span>
            </label>
            <div
              v-if="props.contactId"
              class="flex items-center gap-3 p-2 rounded-lg border border-slate-200 dark:border-slate-600 bg-slate-50 dark:bg-slate-700/50"
            >
              <img
                v-if="contactForDisplay?.avatar_url"
                :src="contactForDisplay.avatar_url"
                class="w-8 h-8 rounded-full flex-shrink-0"
              />
              <span
                v-else
                class="w-8 h-8 rounded-full bg-woot-100 dark:bg-woot-900 flex-shrink-0 flex items-center justify-center text-xs font-bold text-woot-600 dark:text-woot-300"
              >
                {{ contactForDisplay?.name?.[0]?.toUpperCase() }}
              </span>
              <div class="min-w-0">
                <p
                  class="text-sm font-medium text-slate-800 dark:text-slate-100 truncate"
                >
                  {{ contactForDisplay?.name }}
                </p>
                <p
                  v-if="contactForDisplay?.email"
                  class="text-xs text-slate-400 truncate"
                >
                  {{ contactForDisplay.email }}
                </p>
              </div>
            </div>
            <ContactSelector
              v-else
              :contacts="contacts"
              :selected-contact="selectedContact"
              :show-contacts-dropdown="showContactsDropdown"
              :is-loading="isSearching"
              :is-creating-contact="isCreatingContact"
              :contactable-inboxes-list="[]"
              :show-inboxes-dropdown="false"
              @search-contacts="handleSearchContacts"
              @set-selected-contact="handleSetSelectedContact"
              @clear-selected-contact="clearSelectedContact"
            />
          </div>

          <!-- Pipeline selector: only when no activePipeline and no pipelineId prop -->
          <div v-if="showPipelineSelector">
            <label
              class="block text-sm font-medium text-slate-700 dark:text-slate-300 mb-1"
            >
              {{ t('KANBAN.ITEM.PIPELINE_LABEL') }}
            </label>
            <select
              v-model="selectedPipelineId"
              class="w-full px-3 py-2 text-sm border border-slate-200 dark:border-slate-600 rounded-lg bg-white dark:bg-slate-700 text-slate-800 dark:text-slate-100 focus:outline-none focus:ring-2 focus:ring-woot-500"
            >
              <option
                v-for="pipeline in pipelines"
                :key="pipeline.id"
                :value="pipeline.id"
              >
                {{ pipeline.name }}
              </option>
            </select>
          </div>

          <div>
            <label
              class="block text-sm font-medium text-slate-700 dark:text-slate-300 mb-1"
            >
              {{ t('KANBAN.ITEM.STAGE_LABEL') }}
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

          <div class="flex items-center gap-2">
            <input
              id="assign-to-me"
              v-model="assignToMe"
              type="checkbox"
              class="rounded border-slate-300 dark:border-slate-600 text-woot-500 focus:ring-woot-500"
            />
            <label
              for="assign-to-me"
              class="text-sm text-slate-600 dark:text-slate-400 cursor-pointer"
            >
              {{ t('KANBAN.ITEM.ASSIGN_TO_ME') }}
            </label>
          </div>

          <div>
            <label
              class="block text-sm font-medium text-slate-700 dark:text-slate-300 mb-1"
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
              class="block text-sm font-medium text-slate-700 dark:text-slate-300 mb-1"
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
        </div>

        <div
          class="flex items-center justify-end gap-2 px-6 py-4 border-t border-slate-100 dark:border-slate-700"
        >
          <button
            class="px-4 py-2 text-sm text-slate-600 dark:text-slate-400 hover:bg-slate-100 dark:hover:bg-slate-700 rounded-lg transition-colors"
            @click="emit('close')"
          >
            {{ t('KANBAN.ITEM.CANCEL') }}
          </button>
          <button
            class="px-4 py-2 text-sm font-medium text-white bg-woot-500 hover:bg-woot-600 rounded-lg transition-colors disabled:opacity-50 flex items-center gap-2"
            :disabled="
              !(props.contactId || selectedContact) || uiFlags.isCreating
            "
            @click="handleSubmit"
          >
            <span
              v-if="uiFlags.isCreating"
              class="i-lucide-loader size-4 animate-spin"
            />
            {{ t('KANBAN.ITEM.ADD') }}
          </button>
        </div>
      </div>
    </div>
  </Teleport>
</template>
