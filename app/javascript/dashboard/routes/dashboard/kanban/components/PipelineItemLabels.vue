<script setup>
import { ref, computed } from 'vue';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import LabelDropdown from 'shared/components/ui/label/LabelDropdown.vue';

const props = defineProps({
  item: { type: Object, required: true },
});

const store = useStore();
const pipelineLabels = useMapGetter('labels/getPipelineLabels');

const showDropdown = ref(false);
const activeLabels = computed(() => props.item.label_list || []);

const activeLabelObjects = computed(() =>
  pipelineLabels.value.filter(l => activeLabels.value.includes(l.title))
);

const toggleDropdown = () => {
  showDropdown.value = !showDropdown.value;
};

const closeDropdown = () => {
  showDropdown.value = false;
};

const addLabel = async label => {
  if (activeLabels.value.includes(label.title)) return;
  const previous = [...activeLabels.value];
  const updated = [...previous, label.title];
  store.commit('kanban/EDIT_ITEM', { id: props.item.id, label_list: updated });
  try {
    await store.dispatch('kanban/updateItemLabels', {
      itemId: props.item.id,
      labels: updated,
    });
  } catch {
    store.commit('kanban/EDIT_ITEM', {
      id: props.item.id,
      label_list: previous,
    });
  }
};

const removeLabel = async title => {
  const previous = [...activeLabels.value];
  const updated = previous.filter(t => t !== title);
  store.commit('kanban/EDIT_ITEM', { id: props.item.id, label_list: updated });
  try {
    await store.dispatch('kanban/updateItemLabels', {
      itemId: props.item.id,
      labels: updated,
    });
  } catch {
    store.commit('kanban/EDIT_ITEM', {
      id: props.item.id,
      label_list: previous,
    });
  }
};
</script>

<template>
  <div v-on-clickaway="closeDropdown" class="relative flex flex-wrap gap-1">
    <button
      class="flex items-center gap-1 px-2 py-0.5 text-xs rounded border border-dashed border-slate-300 dark:border-slate-600 text-slate-500 dark:text-slate-400 hover:bg-slate-50 dark:hover:bg-slate-700 transition-colors"
      @click="toggleDropdown"
    >
      <span class="i-lucide-plus size-3" />
      {{ t('KANBAN.ITEM.LABELS_ADD') }}
    </button>

    <woot-label
      v-for="label in activeLabelObjects"
      :key="label.title"
      :title="label.title"
      :color="label.color"
      show-close
      variant="smooth"
      @remove="removeLabel"
    />

    <div
      v-if="showDropdown"
      class="absolute top-full ltr:left-0 rtl:right-0 mt-1 z-[9999] w-56 border border-n-strong rounded-lg bg-n-alpha-3 backdrop-blur-[100px] shadow-lg p-2"
    >
      <LabelDropdown
        :account-labels="pipelineLabels"
        :selected-labels="activeLabels"
        :allow-creation="false"
        @add="addLabel"
        @remove="removeLabel"
      />
    </div>
  </div>
</template>
