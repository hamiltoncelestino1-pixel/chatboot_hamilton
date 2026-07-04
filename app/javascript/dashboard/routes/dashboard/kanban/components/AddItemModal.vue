<script setup>
import { ref, reactive, computed, watch, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import ContactAPI from 'dashboard/api/contacts';

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

const contactSearch = ref('');
const contactResults = ref([]);
const selectedContact = ref(null);

const contactForDisplay = computed(() =>
  props.contactId
    ? preselectedContact.value(props.contactId)
    : selectedContact.value
);

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

const showPipelineSelector = computed(
  () => !!props.contactId || (!props.pipelineId && !activePipeline.value)
);

const searchContacts = async () => {
  if (!contactSearch.value.trim()) {
    contactResults.value = [];
    return;
  }
  isSearching.value = true;
  try {
    const { data } = await ContactAPI.search(contactSearch.value, 1);
    contactResults.value = Array.isArray(data?.payload) ? data.payload : [];
  } catch {
    contactResults.value = [];
  } finally {
    isSearching.value = false;
  }
};

const selectContact = contact => {
  selectedContact.value = contact;
  contactSearch.value = contact.name;
  contactResults.value = [];
};

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
  } catch {
    useAlert(t('KANBAN.ITEM.API.ERROR'));
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
            <div v-else class="relative">
              <input
                v-model="contactSearch"
                type="text"
                class="w-full px-3 py-2 text-sm border border-slate-200 dark:border-slate-600 rounded-lg bg-white dark:bg-slate-700 text-slate-800 dark:text-slate-100 focus:outline-none focus:ring-2 focus:ring-woot-500"
                :placeholder="t('KANBAN.ITEM.CONTACT_PLACEHOLDER')"
                @input="searchContacts"
              />
              <div
                v-if="contactResults.length > 0"
                class="absolute top-full left-0 right-0 mt-1 bg-white dark:bg-slate-800 border border-slate-200 dark:border-slate-600 rounded-lg shadow-lg z-10 max-h-48 overflow-y-auto"
              >
                <button
                  v-for="contact in contactResults"
                  :key="contact.id"
                  class="w-full text-left px-3 py-2 text-sm text-slate-700 dark:text-slate-200 hover:bg-slate-50 dark:hover:bg-slate-700 flex items-center gap-2 transition-colors"
                  @click="selectContact(contact)"
                >
                  <img
                    v-if="contact.avatar_url"
                    :src="contact.avatar_url"
                    class="w-6 h-6 rounded-full flex-shrink-0"
                  />
                  <span
                    v-else
                    class="w-6 h-6 rounded-full bg-woot-100 dark:bg-woot-900 flex-shrink-0 flex items-center justify-center text-xs font-bold text-woot-600 dark:text-woot-300"
                  >
                    {{ contact.name?.[0]?.toUpperCase() }}
                  </span>
                  <div class="min-w-0">
                    <p class="truncate font-medium">{{ contact.name }}</p>
                    <p
                      v-if="contact.email"
                      class="text-xs text-slate-400 truncate"
                    >
                      {{ contact.email }}
                    </p>
                  </div>
                </button>
              </div>
            </div>
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
