# Task: Configurações > Pipelines (gestão completa + deleção com confirmação)

## Objetivo

Hoje o CRUD de pipeline e etapa acontece via modais dentro do próprio board Kanban
(`AddPipelineModal.vue`), sem visão geral, sem exclusão pela UI (as actions `deletePipeline`/
`deleteStage` já existem no store `kanban` mas **nenhum botão as usa hoje** — confirmado lendo
`AddPipelineModal.vue`, `PipelineSelector.vue`, `KanbanColumn.vue`), e boa parte do texto está
hardcoded em pt-BR.

Esta task cria **Configurações > Pipelines**, um novo módulo de settings nos moldes de
Configurações > Etiquetas/Atributos Personalizados, que passa a ser o único lugar para:
- Listar pipelines (nome, nº de etapas, nº de oportunidades, nº de agentes atribuídos).
- Criar/editar/**excluir** pipeline (com aviso de cascata).
- Gerenciar etapas de um pipeline (nome, cor, ordem) — criar/editar/**excluir**.
- Gerenciar as etiquetas exclusivas do pipeline (aba, reaproveitando a task
  `10-feat-pipeline-exclusive-labels.md`).
- Gerenciar os agentes atribuídos ao pipeline (aba, reaproveitando a task
  `08/09-feat-pipeline-agent-assignment-*.md`).

O board Kanban (`/accounts/:id/kanban`) deixa de ter os modais de criar/editar/excluir pipeline e
etapa — vira uma tela só de trabalho (ver task `13-feat-kanban-board-refinements.md`).

**Pré-requisitos:** tasks 08, 09 e 10 implementadas (membros, assignee, etiquetas exclusivas).

---

## 1. Rotas — `app/javascript/dashboard/routes/dashboard/settings/pipelines/pipelines.routes.js`

Mirror exato de `settings/labels/labels.routes.js`:

```javascript
import { frontendURL } from '../../../../helper/URLHelper';
import SettingsWrapper from '../SettingsWrapper.vue';
import Index from './Index.vue';
import PipelineDetail from './PipelineDetail.vue';

export default {
  routes: [
    {
      path: frontendURL('accounts/:accountId/settings/pipelines'),
      component: SettingsWrapper,
      children: [
        {
          path: '',
          name: 'pipelines_wrapper',
          meta: { permissions: ['administrator'] },
          redirect: to => ({ name: 'pipelines_list', params: to.params }),
        },
        {
          path: 'list',
          name: 'pipelines_list',
          meta: { permissions: ['administrator'] },
          component: Index,
        },
        {
          path: ':pipelineId',
          name: 'pipelines_show',
          meta: { permissions: ['administrator'] },
          component: PipelineDetail,
        },
      ],
    },
  ],
};
```

### Registrar em `app/javascript/dashboard/routes/dashboard/settings/settings.routes.js`

```javascript
import pipelines from './pipelines/pipelines.routes';
// ...
...pipelines.routes,
```

---

## 2. Sidebar — `app/javascript/dashboard/components-next/sidebar/Sidebar.vue`

Adicionar nova entrada nos children do grupo Settings, junto de "Settings Labels"/"Settings Custom
Attributes" (linha ~645-655 atual):

```javascript
{
  name: 'Settings Pipelines',
  label: t('SIDEBAR.PIPELINES'),
  icon: 'i-lucide-columns-3',
  to: accountScopedRoute('pipelines_list'),
},
```

---

## 3. `settings/pipelines/Index.vue` — lista de pipelines

Seguir exatamente o layout de `settings/labels/Index.vue` (lido integralmente): `SettingsLayout` +
`BaseSettingsHeader` + `BaseTable` + `woot-modal` + `woot-delete-modal`.

```vue
<script setup>
import { computed, onBeforeMount, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useStoreGetters, useStore } from 'dashboard/composables/store';
import { picoSearch } from '@scmmishra/pico-search';
import { useRouter } from 'vue-router';

import AddPipeline from './AddPipeline.vue';
import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';
import SettingsLayout from '../SettingsLayout.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import { BaseTable, BaseTableRow, BaseTableCell } from 'dashboard/components-next/table';

const { t } = useI18n();
const router = useRouter();
const getters = useStoreGetters();
const store = useStore();

const showAddPopup = ref(false);
const showDeletePopup = ref(false);
const selectedPipeline = ref({});
const searchQuery = ref('');
const loading = ref({});

const pipelines = computed(() => getters['kanban/getPipelines'].value);
const uiFlags = computed(() => getters['kanban/getUIFlags'].value);

const filteredPipelines = computed(() => {
  const query = searchQuery.value.trim();
  if (!query) return pipelines.value;
  return picoSearch(pipelines.value, query, [{ name: 'name', weight: 4 }, 'description']);
});

const stagesCount = pipeline =>
  getters['kanban/getStagesForPipeline'].value(pipeline.id)?.length || 0;

onBeforeMount(() => {
  store.dispatch('kanban/fetchPipelines');
});

const openAddPopup = () => { showAddPopup.value = true; };
const hideAddPopup = () => { showAddPopup.value = false; };
const goToDetail = pipeline => {
  router.push({ name: 'pipelines_show', params: { pipelineId: pipeline.id } });
};

const openDeletePopup = pipeline => {
  selectedPipeline.value = pipeline;
  showDeletePopup.value = true;
};
const closeDeletePopup = () => { showDeletePopup.value = false; };

const confirmDeletion = async () => {
  loading.value[selectedPipeline.value.id] = true;
  closeDeletePopup();
  try {
    await store.dispatch('kanban/deletePipeline', selectedPipeline.value.id);
    useAlert(t('PIPELINE_MGMT.DELETE.API.SUCCESS'));
  } catch {
    useAlert(t('PIPELINE_MGMT.DELETE.API.ERROR'));
  } finally {
    loading.value[selectedPipeline.value.id] = false;
  }
};

const deleteMessage = computed(
  () => ` ${selectedPipeline.value.name}? ${t('PIPELINE_MGMT.DELETE.CONFIRM.CASCADE_WARNING', {
    stages: stagesCount(selectedPipeline.value),
  })}`
);
</script>

<template>
  <SettingsLayout
    :is-loading="uiFlags.isFetchingPipelines"
    :loading-message="t('PIPELINE_MGMT.LOADING')"
    :no-records-found="!pipelines.length"
    :no-records-message="t('PIPELINE_MGMT.LIST.404')"
  >
    <template #header>
      <BaseSettingsHeader
        v-model:search-query="searchQuery"
        :title="t('PIPELINE_MGMT.HEADER')"
        :description="t('PIPELINE_MGMT.DESCRIPTION')"
        :search-placeholder="t('PIPELINE_MGMT.SEARCH_PLACEHOLDER')"
      >
        <template #actions>
          <Button :label="t('PIPELINE_MGMT.HEADER_BTN_TXT')" size="sm" @click="openAddPopup" />
        </template>
      </BaseSettingsHeader>
    </template>
    <template #body>
      <BaseTable
        :headers="[
          t('PIPELINE_MGMT.LIST.TABLE_HEADER.NAME'),
          t('PIPELINE_MGMT.LIST.TABLE_HEADER.STAGES'),
          t('PIPELINE_MGMT.LIST.TABLE_HEADER.ACTION'),
        ]"
        :items="filteredPipelines"
      >
        <template #row="{ items }">
          <BaseTableRow v-for="pipeline in items" :key="pipeline.id" :item="pipeline">
            <template #default>
              <BaseTableCell>
                <button class="text-left text-n-blue-11 hover:underline" @click="goToDetail(pipeline)">
                  {{ pipeline.name }}
                </button>
              </BaseTableCell>
              <BaseTableCell>{{ stagesCount(pipeline) }}</BaseTableCell>
              <BaseTableCell align="end">
                <div class="flex gap-3 justify-end">
                  <Button icon="i-woot-edit-pen" slate sm @click="goToDetail(pipeline)" />
                  <Button
                    icon="i-woot-bin"
                    slate
                    sm
                    :is-loading="loading[pipeline.id]"
                    class="hover:enabled:text-n-ruby-11 hover:enabled:bg-n-ruby-2"
                    @click="openDeletePopup(pipeline)"
                  />
                </div>
              </BaseTableCell>
            </template>
          </BaseTableRow>
        </template>
      </BaseTable>
    </template>

    <woot-modal v-model:show="showAddPopup" :on-close="hideAddPopup">
      <AddPipeline @close="hideAddPopup" />
    </woot-modal>

    <woot-delete-modal
      v-model:show="showDeletePopup"
      :on-close="closeDeletePopup"
      :on-confirm="confirmDeletion"
      :title="t('PIPELINE_MGMT.DELETE.CONFIRM.TITLE')"
      :message="t('PIPELINE_MGMT.DELETE.CONFIRM.MESSAGE')"
      :message-value="deleteMessage"
      :confirm-text="t('PIPELINE_MGMT.DELETE.CONFIRM.YES')"
      :reject-text="t('PIPELINE_MGMT.DELETE.CONFIRM.NO')"
    />
  </SettingsLayout>
</template>
```

---

## 4. `settings/pipelines/AddPipeline.vue`

Modal simples reaproveitando a lógica de `kanban/createPipeline` que já existe no store (extraída
do atual `AddPipelineModal.vue` do board, **sem** a parte de criação de stages inline — etapas
passam a ser geridas na tela de detalhe):

```vue
<script setup>
import { reactive } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';

const emit = defineEmits(['close']);
const { t } = useI18n();
const store = useStore();
const uiFlags = useMapGetter('kanban/getUIFlags');
const form = reactive({ name: '', description: '' });

const handleSubmit = async () => {
  if (!form.name.trim()) return;
  try {
    await store.dispatch('kanban/createPipeline', { ...form });
    useAlert(t('PIPELINE_MGMT.ADD.API.SUCCESS'));
    emit('close');
  } catch {
    useAlert(t('PIPELINE_MGMT.ADD.API.ERROR'));
  }
};
</script>

<template>
  <woot-modal-header :header-title="t('PIPELINE_MGMT.ADD.TITLE')" />
  <form class="w-full px-6 pb-6" @submit.prevent="handleSubmit">
    <woot-input
      v-model="form.name"
      :label="t('PIPELINE_MGMT.ADD.FORM.NAME.LABEL')"
      :placeholder="t('PIPELINE_MGMT.ADD.FORM.NAME.PLACEHOLDER')"
    />
    <label>
      {{ t('PIPELINE_MGMT.ADD.FORM.DESCRIPTION.LABEL') }}
      <textarea v-model="form.description" rows="3" />
    </label>
    <div class="flex justify-end gap-2 mt-4">
      <woot-button variant="clear" @click.prevent="emit('close')">
        {{ t('PIPELINE_MGMT.ADD.CANCEL') }}
      </woot-button>
      <woot-button :is-loading="uiFlags.isCreating" type="submit">
        {{ t('PIPELINE_MGMT.ADD.SUBMIT') }}
      </woot-button>
    </div>
  </form>
</template>
```

---

## 5. `settings/pipelines/PipelineDetail.vue` — página com 3 abas

```vue
<script setup>
import { computed, onBeforeMount, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute } from 'vue-router';
import { useStore, useStoreGetters } from 'dashboard/composables/store';
import TabBar from 'dashboard/components-next/tabbar/TabBar.vue';
import SettingsLayout from '../SettingsLayout.vue';
import PipelineStagesSection from './PipelineStagesSection.vue';
import PipelineLabelsSection from './PipelineLabelsSection.vue';
import PipelineMembersSection from './PipelineMembersSection.vue';

const { t } = useI18n();
const route = useRoute();
const store = useStore();
const getters = useStoreGetters();

const pipelineId = computed(() => Number(route.params.pipelineId));
const pipeline = computed(() => getters['kanban/getPipelines'].value.find(p => p.id === pipelineId.value));

const selectedTabIndex = ref(0);
const tabs = computed(() => [
  { key: 0, label: t('PIPELINE_MGMT.DETAIL.TABS.STAGES') },
  { key: 1, label: t('PIPELINE_MGMT.DETAIL.TABS.LABELS') },
  { key: 2, label: t('PIPELINE_MGMT.DETAIL.TABS.AGENTS') },
]);

onBeforeMount(async () => {
  await store.dispatch('kanban/fetchPipelines');
  store.dispatch('pipelineMembers/get', { pipelineId: pipelineId.value });
});
</script>

<template>
  <SettingsLayout>
    <template #header>
      <h2 class="text-lg font-semibold">{{ pipeline?.name }}</h2>
      <TabBar :tabs="tabs" :initial-active-tab="selectedTabIndex" @tab-changed="t => (selectedTabIndex = t.key)" />
    </template>
    <template #body>
      <PipelineStagesSection v-if="selectedTabIndex === 0" :pipeline-id="pipelineId" />
      <PipelineLabelsSection v-if="selectedTabIndex === 1" />
      <PipelineMembersSection v-if="selectedTabIndex === 2" :pipeline-id="pipelineId" />
    </template>
  </SettingsLayout>
</template>
```

### `PipelineStagesSection.vue`

Lista de `PipelineStage` do pipeline (via `kanban/getStagesForPipeline`), CRUD inline (nome + color
picker, reaproveitando `kanban/createStage`/`updateStage`/`deleteStage` já existentes no store —
extraído do atual `AddPipelineModal.vue`/board), reorder por drag (`vuedraggable`, já é dependência
do projeto) chamando `kanban/reorderStages`. Botão deletar etapa usa `woot-delete-modal` com aviso:

```javascript
const itemsInStage = stage => store.getters['kanban/getItemsForStage'](stage.id).length;
```
```html
:message-value="` ${stage.name}? ${t('PIPELINE_MGMT.STAGE.DELETE.CASCADE_WARNING', { items: itemsInStage(stage) })}`"
```

### `PipelineLabelsSection.vue`

Reaproveita `AddLabel.vue`/`EditLabel.vue` (task 10) passando `fixed-label-type="pipeline_label"`,
e a mesma listagem/exclusão de `settings/labels/Index.vue` mas fixando o filtro
`getters['labels/getPipelineLabels']` (sem TabBar aqui, já que o contexto é só pipeline).

### `PipelineMembersSection.vue`

Mirror exato de `app/javascript/dashboard/routes/dashboard/settings/inbox/settingsPage/CollaboratorsPage.vue`
(componente real confirmado por leitura), trocando `inboxMembers` pela store `pipelineMembers`
(task 09) e a prop `inboxId` por `pipelineId`:

```vue
<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useStore, useStoreGetters } from 'dashboard/composables/store';
import TagInput from 'dashboard/components-next/taginput/TagInput.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';

const props = defineProps({ pipelineId: { type: Number, required: true } });
const { t } = useI18n();
const store = useStore();
const getters = useStoreGetters();

const allAgents = computed(() => getters['agents/getAgents'].value);
const currentMembers = computed(() => getters['pipelineMembers/getPipelineMembers'].value(props.pipelineId));
const selectedAgentIds = ref([]);
const isUpdating = computed(() => getters['pipelineMembers/getUIFlags'].value.isUpdating);

onMounted(() => {
  store.dispatch('pipelineMembers/get', { pipelineId: props.pipelineId }).then(() => {
    selectedAgentIds.value = currentMembers.value.map(a => a.id);
  });
});

const agentMenuItems = computed(() =>
  allAgents.value
    .filter(a => !selectedAgentIds.value.includes(a.id))
    .map(a => ({ label: a.name, value: a.id }))
);

const handleAgentAdd = agent => selectedAgentIds.value.push(agent.value);
const handleAgentRemove = agent => {
  selectedAgentIds.value = selectedAgentIds.value.filter(id => id !== agent.value);
};

const handleUpdate = async () => {
  try {
    await store.dispatch('pipelineMembers/update', {
      pipelineId: props.pipelineId,
      agentIds: selectedAgentIds.value,
    });
    useAlert(t('PIPELINE_MGMT.AGENTS.API.SUCCESS'));
  } catch {
    useAlert(t('PIPELINE_MGMT.AGENTS.API.ERROR'));
  }
};
</script>

<template>
  <div class="p-4">
    <TagInput
      :model-value="currentMembers.map(a => a.name)"
      :menu-items="agentMenuItems"
      @add="handleAgentAdd"
      @remove="handleAgentRemove"
    />
    <NextButton
      class="mt-4"
      :label="t('PIPELINE_MGMT.AGENTS.UPDATE')"
      :is-loading="isUpdating"
      @click="handleUpdate"
    />
  </div>
</template>
```

---

## 6. Remover CRUD antigo do board

`app/javascript/dashboard/routes/dashboard/kanban/components/AddPipelineModal.vue` é **excluído**
(sua lógica foi extraída para `settings/pipelines/AddPipeline.vue` + `PipelineStagesSection.vue`).
Qualquer botão que abria esse modal no board (`KanbanIndex.vue`) deve ser removido — ver task
`13-feat-kanban-board-refinements.md` para o restante da limpeza do board.

---

## i18n

Novo bloco `PIPELINE_MGMT` em `en/settings.json` e `pt_BR/settings.json` (seguir exatamente a
estrutura de `LABEL_MGMT`/`ATTRIBUTES_MGMT` já existentes nesses arquivos):

```json
"PIPELINE_MGMT": {
  "HEADER": "Pipelines",
  "DESCRIPTION": "Manage your CRM pipelines, stages, labels and assigned agents.",
  "HEADER_BTN_TXT": "Add pipeline",
  "SEARCH_PLACEHOLDER": "Search pipelines",
  "LOADING": "Loading pipelines...",
  "LIST": {
    "404": "No pipelines found",
    "TABLE_HEADER": { "NAME": "Name", "STAGES": "Stages", "ACTION": "Actions" }
  },
  "ADD": {
    "TITLE": "Add pipeline",
    "FORM": {
      "NAME": { "LABEL": "Name", "PLACEHOLDER": "e.g. Sales" },
      "DESCRIPTION": { "LABEL": "Description" }
    },
    "CANCEL": "Cancel",
    "SUBMIT": "Create",
    "API": { "SUCCESS": "Pipeline created successfully.", "ERROR": "Something went wrong." }
  },
  "DELETE": {
    "CONFIRM": {
      "TITLE": "Delete pipeline",
      "MESSAGE": "Are you sure you want to delete",
      "CASCADE_WARNING": "This will also delete {stages} stage(s) and all its opportunities.",
      "YES": "Yes, delete",
      "NO": "No, keep it"
    },
    "API": { "SUCCESS": "Pipeline deleted successfully.", "ERROR": "Something went wrong." }
  },
  "DETAIL": {
    "TABS": { "STAGES": "Stages", "LABELS": "Labels", "AGENTS": "Agents" }
  },
  "STAGE": {
    "DELETE": { "CASCADE_WARNING": "This will also delete {items} opportunity(ies) in this stage." }
  },
  "AGENTS": {
    "UPDATE": "Update",
    "API": { "SUCCESS": "Agents updated successfully.", "ERROR": "Something went wrong." }
  }
}
```

Traduzir integralmente para `pt_BR`. `SIDEBAR.PIPELINES`: `"Pipelines"` (en) / `"Pipelines"` (pt_BR).

---

## Verificação

1. Configurações > Pipelines lista os pipelines existentes com contagem de etapas.
2. Criar novo pipeline pelo botão — aparece na lista.
3. Clicar num pipeline → tela de detalhe com 3 abas.
4. Aba Etapas: criar, reordenar (drag) e excluir etapa (com aviso de quantas oportunidades serão
   afetadas).
5. Aba Etiquetas: criar/excluir etiqueta exclusiva de pipeline.
6. Aba Agentes: adicionar/remover agentes — confirmar que reflete na task 09 (dropdown de assignee
   no board só lista quem está aqui).
7. Excluir um pipeline pela lista — aviso de cascata, remove etapas e oportunidades
   (`dependent: :destroy_async` já existente nos models).
8. Confirmar que o board Kanban não tem mais nenhum botão de criar/editar/excluir pipeline ou etapa.
