<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import AddItemModal from 'dashboard/routes/dashboard/kanban/components/AddItemModal.vue';

const props = defineProps({
  contactId: { type: Number, required: true },
  conversationId: { type: [Number, String], required: true },
});

const { t } = useI18n();
const store = useStore();
const router = useRouter();

const isFetching = ref(true);
const showAddItemModal = ref(false);

const itemsGetter = useMapGetter('kanban/getItemsForConversation');
const items = computed(() => itemsGetter.value(Number(props.conversationId)));

// A watch, not onMounted: ContactPanel isn't remounted when the agent switches conversation, only
// its conversationId prop changes. The getter above reads an index that's populated solely by
// this fetch (task 25), so it has to run for every conversation shown, not just the first.
watch(
  () => props.conversationId,
  async conversationId => {
    isFetching.value = true;
    try {
      await store.dispatch('kanban/fetchItemsForConversation', conversationId);
    } finally {
      isFetching.value = false;
    }
  },
  { immediate: true }
);

const goToOpportunity = item => {
  router.push({
    name: 'kanban_index',
    query: { pipelineId: item.pipeline_id, itemId: item.id },
  });
};

const onCreated = () => {
  showAddItemModal.value = false;
  store.dispatch('kanban/fetchItemsForConversation', props.conversationId);
};
</script>

<template>
  <div class="px-4 py-3">
    <div v-if="isFetching" class="flex justify-center py-4">
      <span class="i-lucide-loader size-5 animate-spin text-slate-400" />
    </div>
    <template v-else>
      <div v-if="!items.length" class="text-center py-3">
        <p class="text-sm text-n-slate-11 mb-3">
          {{ t('CONVERSATION_SIDEBAR.OPPORTUNITIES.EMPTY_STATE') }}
        </p>
        <button
          class="px-3 py-1.5 text-sm font-medium text-white bg-woot-500 hover:bg-woot-600 rounded-lg transition-colors"
          @click="showAddItemModal = true"
        >
          {{ t('CONVERSATION_SIDEBAR.OPPORTUNITIES.CREATE') }}
        </button>
      </div>
      <div v-else class="space-y-2">
        <button
          v-for="item in items"
          :key="item.id"
          class="w-full text-left p-2 rounded-lg border border-n-weak hover:bg-n-alpha-1 transition-colors"
          @click="goToOpportunity(item)"
        >
          <p class="text-sm font-medium text-n-slate-12 truncate">
            {{ item.title || item.contact?.name }}
          </p>
          <p class="text-xs text-n-slate-11">
            {{ item.pipeline_name }} · {{ item.pipeline_stage_name }}
          </p>
        </button>
        <button
          class="text-sm text-woot-500 hover:text-woot-600 font-medium transition-colors"
          @click="showAddItemModal = true"
        >
          + {{ t('CONVERSATION_SIDEBAR.OPPORTUNITIES.CREATE') }}
        </button>
      </div>
    </template>

    <AddItemModal
      v-if="showAddItemModal"
      :contact-id="contactId"
      :conversation-id="Number(conversationId)"
      @close="showAddItemModal = false"
      @created="onCreated"
    />
  </div>
</template>
