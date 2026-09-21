<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useStore, useStoreGetters } from 'dashboard/composables/store';
import draggable from 'vuedraggable';

const props = defineProps({
  pipelineId: { type: Number, required: true },
});

const { t } = useI18n();
const store = useStore();
const getters = useStoreGetters();

const stages = computed(
  () => getters['kanban/getStagesForPipeline'].value(props.pipelineId) || []
);

const draggableStages = computed({
  get: () => stages.value,
  set: async newOrder => {
    const orderedIds = newOrder.map(s => s.id);
    try {
      await store.dispatch('kanban/reorderStages', {
        pipelineId: props.pipelineId,
        orderedIds,
      });
    } catch {
      useAlert(t('PIPELINE_MGMT.STAGE.API.ERROR'));
    }
  },
});

const newStage = ref({ name: '', color: '#1f93ff' });
const showAddForm = ref(false);
const editingStageId = ref(null);
const editForm = ref({ name: '', color: '' });
const showDeleteModal = ref(false);
const selectedStage = ref(null);
const isCreating = ref(false);
const isSaving = ref(false);

// stage.items_count comes straight from the API (_pipeline_stage.json.jbuilder, task 01) - the
// board's store only ever holds whatever page of cards was last fetched for that stage (task 05),
// which can be 0 if the agent never opened this pipeline's board at all.
const itemsInStage = stage => stage.items_count || 0;

const startEdit = stage => {
  editingStageId.value = stage.id;
  editForm.value = { name: stage.name, color: stage.color };
};

const cancelEdit = () => {
  editingStageId.value = null;
};

const saveEdit = async stage => {
  if (!editForm.value.name.trim()) return;
  isSaving.value = true;
  try {
    await store.dispatch('kanban/updateStage', {
      pipelineId: props.pipelineId,
      stageId: stage.id,
      name: editForm.value.name,
      color: editForm.value.color,
    });
    editingStageId.value = null;
  } catch {
    useAlert(t('PIPELINE_MGMT.STAGE.API.ERROR'));
  } finally {
    isSaving.value = false;
  }
};

const openDeleteModal = stage => {
  selectedStage.value = stage;
  showDeleteModal.value = true;
};

const confirmDelete = async () => {
  try {
    await store.dispatch('kanban/deleteStage', {
      pipelineId: props.pipelineId,
      stageId: selectedStage.value.id,
    });
    useAlert(t('PIPELINE_MGMT.STAGE.API.DELETE_SUCCESS'));
  } catch {
    useAlert(t('PIPELINE_MGMT.STAGE.API.ERROR'));
  } finally {
    showDeleteModal.value = false;
    selectedStage.value = null;
  }
};

const addStage = async () => {
  if (!newStage.value.name.trim()) return;
  isCreating.value = true;
  try {
    await store.dispatch('kanban/createStage', {
      pipelineId: props.pipelineId,
      name: newStage.value.name,
      color: newStage.value.color,
      position: stages.value.length,
    });
    newStage.value = { name: '', color: '#1f93ff' };
    showAddForm.value = false;
  } catch {
    useAlert(t('PIPELINE_MGMT.STAGE.API.ERROR'));
  } finally {
    isCreating.value = false;
  }
};
</script>

<template>
  <div class="space-y-3">
    <draggable
      v-model="draggableStages"
      handle=".drag-handle"
      item-key="id"
      class="space-y-2"
    >
      <template #item="{ element: stage }">
        <div
          class="flex items-center gap-3 p-3 border border-n-weak rounded-lg bg-white dark:bg-n-solid-2"
        >
          <span
            v-if="stage.stage_type === 'normal'"
            class="drag-handle i-lucide-grip-vertical size-4 text-n-slate-9 cursor-grab"
          />
          <span v-else class="size-4 flex-shrink-0" />
          <div
            class="w-4 h-4 rounded-full flex-shrink-0 border border-n-weak"
            :style="{
              backgroundColor:
                editingStageId === stage.id ? editForm.color : stage.color,
            }"
          />

          <template v-if="editingStageId === stage.id">
            <input
              v-model="editForm.color"
              type="color"
              class="w-8 h-8 rounded cursor-pointer border-0 p-0.5 bg-transparent flex-shrink-0"
            />
            <input
              v-model="editForm.name"
              type="text"
              class="flex-1 px-2 py-1 text-sm border border-n-weak rounded-lg bg-white dark:bg-n-solid-3 text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-woot-500"
              @keyup.enter="saveEdit(stage)"
              @keyup.escape="cancelEdit"
            />
            <button
              class="text-woot-500 hover:text-woot-600 text-sm font-medium"
              :disabled="isSaving"
              @click="saveEdit(stage)"
            >
              {{ t('PIPELINE_MGMT.FORM.SAVE') }}
            </button>
            <button
              class="text-n-slate-9 hover:text-n-slate-11 text-sm"
              @click="cancelEdit"
            >
              {{ t('PIPELINE_MGMT.FORM.CANCEL') }}
            </button>
          </template>
          <template v-else>
            <span class="flex-1 text-sm text-n-slate-12">{{ stage.name }}</span>
            <button
              class="text-n-slate-9 hover:text-n-slate-11 transition-colors"
              @click="startEdit(stage)"
            >
              <span class="i-woot-edit-pen size-4" />
            </button>
            <span
              v-if="stage.stage_type !== 'normal'"
              class="text-n-slate-6 cursor-not-allowed"
              :title="t('PIPELINE_MGMT.STAGE.DELETE.LOCKED')"
            >
              <span class="i-lucide-lock size-4" />
            </span>
            <button
              v-else
              class="text-n-slate-9 hover:text-n-ruby-11 transition-colors"
              @click="openDeleteModal(stage)"
            >
              <span class="i-woot-bin size-4" />
            </button>
          </template>
        </div>
      </template>
    </draggable>

    <div
      v-if="showAddForm"
      class="flex items-center gap-2 p-3 border border-dashed border-n-weak rounded-lg"
    >
      <input
        v-model="newStage.color"
        type="color"
        class="w-8 h-8 rounded cursor-pointer border-0 p-0.5 bg-transparent flex-shrink-0"
      />
      <input
        v-model="newStage.name"
        type="text"
        class="flex-1 px-2 py-1 text-sm border border-n-weak rounded-lg bg-white dark:bg-n-solid-3 text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-woot-500"
        :placeholder="t('PIPELINE_MGMT.STAGE.NAME_PLACEHOLDER')"
        autofocus
        @keyup.enter="addStage"
        @keyup.escape="showAddForm = false"
      />
      <button
        class="text-woot-500 hover:text-woot-600 text-sm font-medium disabled:opacity-50"
        :disabled="isCreating || !newStage.name.trim()"
        @click="addStage"
      >
        {{ t('PIPELINE_MGMT.FORM.SAVE') }}
      </button>
      <button
        class="text-n-slate-9 hover:text-n-slate-11 text-sm"
        @click="showAddForm = false"
      >
        {{ t('PIPELINE_MGMT.FORM.CANCEL') }}
      </button>
    </div>

    <button
      v-if="!showAddForm"
      class="flex items-center gap-2 px-3 py-2 text-sm text-woot-500 hover:text-woot-600 hover:bg-woot-50 dark:hover:bg-woot-900/20 rounded-lg transition-colors"
      @click="showAddForm = true"
    >
      <span class="i-lucide-plus size-4" />
      {{ t('PIPELINE_MGMT.STAGE.ADD') }}
    </button>

    <woot-delete-modal
      v-model:show="showDeleteModal"
      :on-close="() => (showDeleteModal = false)"
      :on-confirm="confirmDelete"
      :title="t('PIPELINE_MGMT.STAGE.DELETE.TITLE')"
      :message="t('PIPELINE_MGMT.STAGE.DELETE.MESSAGE')"
      :message-value="
        selectedStage
          ? ` ${selectedStage.name}? ${t('PIPELINE_MGMT.STAGE.DELETE.CASCADE_WARNING', { items: itemsInStage(selectedStage) })}`
          : ''
      "
      :confirm-text="t('PIPELINE_MGMT.DELETE.CONFIRM.YES')"
      :reject-text="t('PIPELINE_MGMT.DELETE.CONFIRM.NO')"
    />
  </div>
</template>
