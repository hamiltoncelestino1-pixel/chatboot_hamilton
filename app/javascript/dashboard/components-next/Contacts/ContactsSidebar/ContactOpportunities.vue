<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import AddItemModal from 'dashboard/routes/dashboard/kanban/components/AddItemModal.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';

const props = defineProps({
  contactId: { type: Number, required: true },
});

const { t } = useI18n();
const store = useStore();
const router = useRouter();

const isFetching = ref(true);
const showAddItemModal = ref(false);

const itemsGetter = useMapGetter('kanban/getItemsForContact');
const items = computed(() => itemsGetter.value(props.contactId));

onMounted(async () => {
  try {
    await store.dispatch('kanban/fetchItemsForContact', props.contactId);
  } finally {
    isFetching.value = false;
  }
});

const goToOpportunity = item => {
  router.push({
    name: 'kanban_index',
    query: { pipelineId: item.pipeline_id, itemId: item.id },
  });
};

const onCreated = () => {
  showAddItemModal.value = false;
  store.dispatch('kanban/fetchItemsForContact', props.contactId);
};
</script>

<template>
  <div
    v-if="isFetching"
    class="flex items-center justify-center py-10 text-n-slate-11"
  >
    <Spinner />
  </div>
  <template v-else>
    <div v-if="!items.length" class="px-6 py-10 text-center">
      <p class="text-sm text-n-slate-11 mb-3">
        {{ t('CONTACTS_LAYOUT.SIDEBAR.OPPORTUNITIES.EMPTY_STATE') }}
      </p>
      <button
        class="px-3 py-1.5 text-sm font-medium text-white bg-woot-500 hover:bg-woot-600 rounded-lg transition-colors"
        @click="showAddItemModal = true"
      >
        {{ t('CONTACTS_LAYOUT.SIDEBAR.OPPORTUNITIES.CREATE') }}
      </button>
    </div>
    <div v-else class="px-6 py-4 divide-y divide-n-strong">
      <button
        v-for="item in items"
        :key="item.id"
        class="w-full text-left py-3 hover:bg-n-alpha-1 transition-colors"
        @click="goToOpportunity(item)"
      >
        <p class="text-sm font-medium text-n-slate-12 truncate">
          {{
            item.title || t('CONTACTS_LAYOUT.SIDEBAR.OPPORTUNITIES.UNTITLED')
          }}
        </p>
        <p class="text-xs text-n-slate-11">
          {{ item.pipeline_name }} · {{ item.pipeline_stage_name }}
        </p>
        <p
          v-if="item.value"
          class="text-xs text-emerald-600 dark:text-emerald-400 mt-0.5"
        >
          {{ item.value }}
        </p>
      </button>
      <div class="pt-3">
        <button
          class="text-sm text-woot-500 hover:text-woot-600 font-medium transition-colors"
          @click="showAddItemModal = true"
        >
          + {{ t('CONTACTS_LAYOUT.SIDEBAR.OPPORTUNITIES.CREATE') }}
        </button>
      </div>
    </div>
  </template>

  <AddItemModal
    v-if="showAddItemModal"
    :contact-id="contactId"
    @close="showAddItemModal = false"
    @created="onCreated"
  />
</template>
