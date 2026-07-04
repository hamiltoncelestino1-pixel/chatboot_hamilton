# Task: Kanban / CRM Pipeline — Frontend (Vue + Vuex)

## Objetivo

Criar o módulo de interface do Kanban CRM: API client, store Vuex, componentes Vue com drag-and-drop, rota, link na sidebar e i18n — tudo seguindo os padrões já estabelecidos no projeto.

**Pré-requisito:** Task `06-feat-kanban-pipeline-backend.md` implementada (API disponível).

**Dependência de DnD:** `vuedraggable` v4.1.0 já está instalado no `package.json` — não precisa instalar nada.

---

## 1. API Client (`app/javascript/dashboard/api/`)

### `pipelines.js`

Seguir padrão de `app/javascript/dashboard/api/contacts.js` (herda `ApiClient`):

```javascript
import ApiClient from './ApiClient';
import axios from 'axios';

class PipelinesAPI extends ApiClient {
  constructor() {
    super('pipelines', { accountScoped: true });
  }

  getWithStages(id) {
    return axios.get(`${this.url}/${id}`);
  }

  reorderStages(pipelineId, orderedIds) {
    return axios.post(
      `${this.url}/${pipelineId}/pipeline_stages/reorder`,
      { ordered_ids: orderedIds }
    );
  }

  getItems(pipelineId, stageId = null) {
    const params = stageId ? `?stage_id=${stageId}` : '';
    return axios.get(`${this.url}/${pipelineId}/pipeline_items${params}`);
  }
}

export default new PipelinesAPI();
```

### `pipelineItems.js`

```javascript
import ApiClient from './ApiClient';
import axios from 'axios';

class PipelineItemsAPI extends ApiClient {
  constructor() {
    super('pipeline_items', { accountScoped: true });
  }

  reorder(stageId, orderedIds) {
    return axios.post(`${this.url}/reorder`, {
      stage_id: stageId,
      ordered_ids: orderedIds,
    });
  }
}

export default new PipelineItemsAPI();
```

---

## 2. Vuex Store (`app/javascript/dashboard/store/modules/kanban/`)

Seguir estrutura de `store/modules/contacts/` (4 arquivos separados).

### `index.js`
```javascript
import { getters } from './getters';
import { actions } from './actions';
import mutations from './mutations';

const state = {
  pipelines: {},           // { [id]: pipeline }
  stages: {},              // { [id]: stage }
  items: {},               // { [id]: item }
  pipelineOrder: [],       // [id, id, ...] — ordem dos pipelines
  stageOrder: {},          // { [pipeline_id]: [stage_id, ...] }
  itemOrder: {},           // { [stage_id]: [item_id, ...] }
  activePipelineId: null,
  uiFlags: {
    isFetchingPipelines: false,
    isFetchingItems: false,
    isCreating: false,
    isUpdating: false,
    isDeleting: false,
  },
};

export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};
```

### `mutations.js`

Mutation types: `SET_KANBAN_UI_FLAG`, `SET_PIPELINES`, `SET_PIPELINE_ITEM`, `EDIT_PIPELINE`, `DELETE_PIPELINE`, `SET_STAGES`, `SET_STAGE_ITEM`, `EDIT_STAGE`, `DELETE_STAGE`, `SET_ITEMS`, `SET_ITEM`, `EDIT_ITEM`, `DELETE_ITEM`, `MOVE_ITEM`, `SET_ACTIVE_PIPELINE`, `REORDER_STAGES`, `REORDER_ITEMS`

Padrão de cada mutation (normalização — keyed by id):
```javascript
SET_PIPELINES(state, pipelines) {
  const records = {};
  const order = [];
  pipelines.forEach(p => {
    records[p.id] = p;
    order.push(p.id);
    // extrair stages embutidos
    if (p.stages) {
      p.stages.forEach(s => {
        state.stages[s.id] = s;
      });
      state.stageOrder[p.id] = p.stages.map(s => s.id);
    }
  });
  state.pipelines = records;
  state.pipelineOrder = order;
},

MOVE_ITEM(state, { itemId, fromStageId, toStageId, position }) {
  // Remove do stageOrder de origem
  state.itemOrder[fromStageId] = (state.itemOrder[fromStageId] || [])
    .filter(id => id !== itemId);
  // Insere na posição correta do destino
  const destOrder = [...(state.itemOrder[toStageId] || [])];
  destOrder.splice(position, 0, itemId);
  state.itemOrder[toStageId] = destOrder;
  // Atualiza pipeline_stage_id no record
  state.items[itemId] = { ...state.items[itemId], pipeline_stage_id: toStageId };
},
```

Adicionar mutation types em `app/javascript/dashboard/store/mutation-types.js`:
```javascript
// Kanban
export const SET_KANBAN_UI_FLAG = 'SET_KANBAN_UI_FLAG';
// ... (demais types)
```

### `actions.js`

```javascript
export const actions = {
  fetchPipelines: async ({ commit }) => {
    commit('SET_KANBAN_UI_FLAG', { isFetchingPipelines: true });
    try {
      const { data } = await PipelinesAPI.get();
      commit('SET_PIPELINES', data);
    } finally {
      commit('SET_KANBAN_UI_FLAG', { isFetchingPipelines: false });
    }
  },

  fetchItems: async ({ commit }, pipelineId) => {
    commit('SET_KANBAN_UI_FLAG', { isFetchingItems: true });
    try {
      const { data } = await PipelinesAPI.getItems(pipelineId);
      commit('SET_ITEMS', data);
    } finally {
      commit('SET_KANBAN_UI_FLAG', { isFetchingItems: false });
    }
  },

  createPipeline: async ({ commit }, pipelineData) => {
    commit('SET_KANBAN_UI_FLAG', { isCreating: true });
    try {
      const { data } = await PipelinesAPI.create({ pipeline: pipelineData });
      commit('SET_PIPELINE_ITEM', data);
      return data;
    } finally {
      commit('SET_KANBAN_UI_FLAG', { isCreating: false });
    }
  },

  moveItem: async ({ commit }, { itemId, fromStageId, toStageId, position }) => {
    // Optimistic update
    commit('MOVE_ITEM', { itemId, fromStageId, toStageId, position });
    try {
      await PipelineItemsAPI.update(itemId, {
        pipeline_item: { pipeline_stage_id: toStageId, position },
      });
    } catch {
      // Rollback
      commit('MOVE_ITEM', { itemId, fromStageId: toStageId, toStageId: fromStageId, position: 0 });
      useAlert('Erro ao mover card. Tente novamente.');
    }
  },

  reorderStages: async ({ commit }, { pipelineId, orderedIds }) => {
    commit('REORDER_STAGES', { pipelineId, orderedIds });
    await PipelinesAPI.reorderStages(pipelineId, orderedIds);
  },

  // createStage, updatePipeline, deletePipeline, createItem, updateItem, deleteItem...
};
```

### `getters.js`

```javascript
export const getters = {
  getPipelines: state =>
    state.pipelineOrder.map(id => state.pipelines[id]).filter(Boolean),

  getActivePipeline: state =>
    state.pipelines[state.activePipelineId] || null,

  getStagesForPipeline: state => pipelineId =>
    (state.stageOrder[pipelineId] || [])
      .map(id => state.stages[id])
      .filter(Boolean),

  getItemsForStage: state => stageId =>
    (state.itemOrder[stageId] || [])
      .map(id => state.items[id])
      .filter(Boolean),

  getUIFlags: state => state.uiFlags,
};
```

### Registrar o módulo

**`app/javascript/dashboard/store/index.js`** — adicionar:
```javascript
import kanban from './modules/kanban';
// ...
modules: {
  // ...
  kanban,
}
```

---

## 3. Componentes Vue

### Estrutura de arquivos

```
app/javascript/dashboard/routes/dashboard/kanban/
├── routes.js
├── pages/
│   └── KanbanIndex.vue
└── components/
    ├── KanbanBoard.vue
    ├── KanbanColumn.vue
    ├── KanbanCard.vue
    ├── KanbanCardDetail.vue
    ├── KanbanEmptyState.vue
    ├── PipelineSelector.vue
    ├── AddPipelineModal.vue
    └── AddItemModal.vue
```

---

### `KanbanIndex.vue` (página container)

```vue
<script setup>
import { onMounted, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import KanbanBoard from '../components/KanbanBoard.vue';
import KanbanEmptyState from '../components/KanbanEmptyState.vue';
import PipelineSelector from '../components/PipelineSelector.vue';

const { t } = useI18n();
const store = useStore();
const pipelines = useMapGetter('kanban/getPipelines');
const activePipeline = useMapGetter('kanban/getActivePipeline');
const uiFlags = useMapGetter('kanban/getUIFlags');

const hasPipelines = computed(() => pipelines.value.length > 0);

onMounted(async () => {
  await store.dispatch('kanban/fetchPipelines');
  if (hasPipelines.value) {
    const first = pipelines.value[0];
    store.commit('kanban/SET_ACTIVE_PIPELINE', first.id);
    await store.dispatch('kanban/fetchItems', first.id);
  }
});
</script>

<template>
  <div class="flex flex-col h-full">
    <div class="flex items-center justify-between px-4 py-3 border-b border-slate-100 dark:border-slate-800">
      <PipelineSelector v-if="hasPipelines" />
      <button @click="openCreateModal" class="...">
        {{ t('KANBAN.PIPELINE.CREATE') }}
      </button>
    </div>
    <KanbanEmptyState v-if="!hasPipelines && !uiFlags.isFetchingPipelines" />
    <KanbanBoard v-else-if="activePipeline" />
  </div>
</template>
```

---

### `KanbanBoard.vue` (drag-and-drop entre colunas)

```vue
<script setup>
import draggable from 'vuedraggable';
import { computed } from 'vue';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import KanbanColumn from './KanbanColumn.vue';

const store = useStore();
const activePipeline = useMapGetter('kanban/getActivePipeline');
const getStagesForPipeline = useMapGetter('kanban/getStagesForPipeline');

const stages = computed(() =>
  getStagesForPipeline.value(activePipeline.value?.id)
);

const handleStageReorder = async ({ newIndex, oldIndex }) => {
  if (newIndex === oldIndex) return;
  const orderedIds = stages.value.map(s => s.id);
  await store.dispatch('kanban/reorderStages', {
    pipelineId: activePipeline.value.id,
    orderedIds,
  });
};

const handleCardMove = async ({ itemId, fromStageId, toStageId, position }) => {
  await store.dispatch('kanban/moveItem', { itemId, fromStageId, toStageId, position });
};
</script>

<template>
  <div class="flex flex-1 overflow-x-auto gap-4 p-4">
    <draggable
      v-model="stages"
      group="stages"
      item-key="id"
      class="flex gap-4"
      handle=".stage-handle"
      :animation="200"
      @end="handleStageReorder"
    >
      <template #item="{ element: stage }">
        <KanbanColumn :stage="stage" @card-move="handleCardMove" />
      </template>
    </draggable>
    <button @click="openAddStageModal" class="flex-shrink-0 ...">
      + {{ $t('KANBAN.STAGE.ADD') }}
    </button>
  </div>
</template>
```

---

### `KanbanColumn.vue` (coluna de uma stage)

```vue
<script setup>
import draggable from 'vuedraggable';
import { computed, ref } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import KanbanCard from './KanbanCard.vue';

const props = defineProps({
  stage: { type: Object, required: true },
});
const emit = defineEmits(['card-move']);

const getItemsForStage = useMapGetter('kanban/getItemsForStage');
const items = computed(() => getItemsForStage.value(props.stage.id));

const handleAdd = ({ item, newIndex }) => {
  const itemId = Number(item.dataset.id);
  emit('card-move', {
    itemId,
    fromStageId: item.dataset.stageId ? Number(item.dataset.stageId) : null,
    toStageId: props.stage.id,
    position: newIndex,
  });
};
</script>

<template>
  <div class="flex flex-col w-72 flex-shrink-0 rounded-lg bg-slate-50 dark:bg-slate-800">
    <!-- Header da coluna -->
    <div
      class="stage-handle flex items-center justify-between px-3 py-2 rounded-t-lg cursor-grab"
      :style="{ borderTop: `3px solid ${stage.color}` }"
    >
      <span class="text-sm font-semibold text-slate-700 dark:text-slate-200">
        {{ stage.name }}
      </span>
      <span class="text-xs text-slate-400">{{ items.length }}</span>
    </div>

    <!-- Cards com DnD -->
    <draggable
      v-model="items"
      group="items"
      item-key="id"
      class="flex flex-col gap-2 p-2 min-h-[200px]"
      :animation="150"
      @add="handleAdd"
    >
      <template #item="{ element: item }">
        <KanbanCard
          :item="item"
          :data-id="item.id"
          :data-stage-id="stage.id"
        />
      </template>
    </draggable>

    <!-- Botão adicionar card -->
    <button @click="$emit('add-item', stage.id)" class="m-2 text-sm text-slate-400 hover:text-slate-600">
      + {{ $t('KANBAN.ITEM.ADD') }}
    </button>
  </div>
</template>
```

---

### `KanbanCard.vue` (card individual)

```vue
<script setup>
import { computed } from 'vue';

const props = defineProps({
  item: { type: Object, required: true },
});
const emit = defineEmits(['click']);

const formattedValue = computed(() => {
  if (!props.item.value) return null;
  return new Intl.NumberFormat('pt-BR', {
    style: 'currency',
    currency: 'BRL',
  }).format(props.item.value);
});
</script>

<template>
  <div
    class="bg-white dark:bg-slate-700 rounded-md p-3 shadow-sm cursor-pointer hover:shadow-md transition-shadow"
    @click="emit('click', item)"
  >
    <!-- Avatar + Nome do contato -->
    <div class="flex items-center gap-2 mb-2">
      <img
        v-if="item.contact?.avatar_url"
        :src="item.contact.avatar_url"
        class="w-6 h-6 rounded-full"
      />
      <span class="text-sm font-medium text-slate-700 dark:text-slate-200 truncate">
        {{ item.title || item.contact?.name }}
      </span>
    </div>

    <!-- Valor monetário -->
    <div v-if="formattedValue" class="text-xs text-slate-500">
      {{ formattedValue }}
    </div>

    <!-- Link para conversa -->
    <div v-if="item.conversation_id" class="mt-1 text-xs text-woot-500">
      #{{ item.conversation_id }}
    </div>
  </div>
</template>
```

---

### `KanbanCardDetail.vue` (slide-over com detalhes)

Slide-over abre ao clicar num card. Mostra:
- Informações do contato (nome, email, telefone, avatar)
- Campos editáveis: título, valor, notes
- Link para a conversa (se houver)
- Seletor de stage para mover
- Botão deletar (só admin)

Seguir padrão dos slide-overs já existentes em `components-next/` (procurar um componente existente com `transition` + `fixed inset-0` como referência visual).

---

### `PipelineSelector.vue` (dropdown de pipelines)

```vue
<script setup>
import { useStore, useMapGetter } from 'dashboard/composables/store';

const store = useStore();
const pipelines = useMapGetter('kanban/getPipelines');
const activePipeline = useMapGetter('kanban/getActivePipeline');

const selectPipeline = async pipeline => {
  store.commit('kanban/SET_ACTIVE_PIPELINE', pipeline.id);
  await store.dispatch('kanban/fetchItems', pipeline.id);
};
</script>
```

### `AddPipelineModal.vue`

Modal para criar pipeline com campos: `name`, `description`. Opcionalmente permite adicionar stages iniciais em linha (nome + cor por stage). Ao submeter: dispatch `kanban/createPipeline` + `kanban/createStage` para cada stage.

### `AddItemModal.vue`

Modal para adicionar card a uma stage. Campo de busca de contato (autocomplete chamando `contacts/search` do store existente). Campos opcionais: título, valor. Ao submeter: dispatch `kanban/createItem`.

---

## 4. Rota frontend (`routes.js`)

```javascript
import { frontendURL } from 'dashboard/helper/URLHelper';
const KanbanIndex = () => import('./pages/KanbanIndex.vue');

export const routes = [
  {
    path: frontendURL('accounts/:accountId/kanban'),
    name: 'kanban_index',
    component: KanbanIndex,
    meta: {
      permissions: ['administrator', 'agent'],
    },
  },
];
```

### Registrar em `app/javascript/dashboard/routes/dashboard/dashboard.routes.js`

```javascript
import { routes as kanbanRoutes } from './kanban/routes';
// ...
const routes = [
  // ...
  ...kanbanRoutes,
];
```

---

## 5. Sidebar — adicionar ícone de navegação

Localizar o arquivo que define os itens do sidebar principal (provavelmente `app/javascript/dashboard/components-next/layout/Sidebar.vue` ou `app/javascript/dashboard/components/layout/primaryNavigation.js`).

Buscar por onde outros ícones como "Contacts" e "Reports" são definidos e adicionar:

```javascript
{
  icon: 'kanban',          // ícone Phosphor 'ph-kanban' ou 'ph-columns'
  label: 'KANBAN',
  key: 'kanban',
  toState: frontendURL(`accounts/${accountId}/kanban`),
  toStateName: 'kanban_index',
  roles: ['administrator', 'agent'],
},
```

Adicionar também a chave i18n do sidebar em `app/javascript/dashboard/i18n/locale/en/` e `pt_BR/`:
```json
"KANBAN": "Pipeline"
```

---

## 6. i18n

### `app/javascript/dashboard/i18n/locale/en/kanban.json`

```json
{
  "KANBAN": {
    "TITLE": "Pipeline",
    "EMPTY_STATE": {
      "TITLE": "No pipelines yet",
      "DESCRIPTION": "Create your first pipeline to organize and manage your opportunities.",
      "BUTTON": "Create Pipeline"
    },
    "PIPELINE": {
      "CREATE": "Create Pipeline",
      "EDIT": "Edit Pipeline",
      "DELETE": "Delete Pipeline",
      "NAME_LABEL": "Pipeline name",
      "NAME_PLACEHOLDER": "e.g. Sales Funnel",
      "DESCRIPTION_LABEL": "Description",
      "API": {
        "CREATE_SUCCESS": "Pipeline created successfully.",
        "UPDATE_SUCCESS": "Pipeline updated successfully.",
        "DELETE_SUCCESS": "Pipeline deleted successfully.",
        "ERROR": "Something went wrong. Please try again."
      }
    },
    "STAGE": {
      "ADD": "Add stage",
      "EDIT": "Edit stage",
      "DELETE": "Remove stage",
      "NAME_LABEL": "Stage name",
      "COLOR_LABEL": "Color",
      "API": {
        "CREATE_SUCCESS": "Stage added successfully.",
        "UPDATE_SUCCESS": "Stage updated successfully.",
        "DELETE_SUCCESS": "Stage removed successfully.",
        "ERROR": "Something went wrong. Please try again."
      }
    },
    "ITEM": {
      "ADD": "Add card",
      "EDIT": "Edit card",
      "DELETE": "Delete card",
      "MOVE": "Move to stage",
      "CONTACT_LABEL": "Contact",
      "CONTACT_PLACEHOLDER": "Search contact...",
      "TITLE_LABEL": "Title",
      "VALUE_LABEL": "Deal value",
      "NOTES_LABEL": "Notes",
      "LINKED_CONVERSATION": "Linked conversation",
      "MOVE_ERROR": "Failed to move card. Please try again.",
      "API": {
        "CREATE_SUCCESS": "Card added successfully.",
        "UPDATE_SUCCESS": "Card updated successfully.",
        "DELETE_SUCCESS": "Card deleted successfully.",
        "ERROR": "Something went wrong. Please try again."
      }
    }
  }
}
```

### `app/javascript/dashboard/i18n/locale/pt_BR/kanban.json`

```json
{
  "KANBAN": {
    "TITLE": "Pipeline",
    "EMPTY_STATE": {
      "TITLE": "Nenhum pipeline ainda",
      "DESCRIPTION": "Crie seu primeiro pipeline para organizar e gerenciar suas oportunidades.",
      "BUTTON": "Criar Pipeline"
    },
    "PIPELINE": {
      "CREATE": "Criar Pipeline",
      "EDIT": "Editar Pipeline",
      "DELETE": "Excluir Pipeline",
      "NAME_LABEL": "Nome do pipeline",
      "NAME_PLACEHOLDER": "ex: Funil de Vendas",
      "DESCRIPTION_LABEL": "Descrição",
      "API": {
        "CREATE_SUCCESS": "Pipeline criado com sucesso.",
        "UPDATE_SUCCESS": "Pipeline atualizado com sucesso.",
        "DELETE_SUCCESS": "Pipeline excluído com sucesso.",
        "ERROR": "Algo deu errado. Tente novamente."
      }
    },
    "STAGE": {
      "ADD": "Adicionar etapa",
      "EDIT": "Editar etapa",
      "DELETE": "Remover etapa",
      "NAME_LABEL": "Nome da etapa",
      "COLOR_LABEL": "Cor",
      "API": {
        "CREATE_SUCCESS": "Etapa adicionada com sucesso.",
        "UPDATE_SUCCESS": "Etapa atualizada com sucesso.",
        "DELETE_SUCCESS": "Etapa removida com sucesso.",
        "ERROR": "Algo deu errado. Tente novamente."
      }
    },
    "ITEM": {
      "ADD": "Adicionar card",
      "EDIT": "Editar card",
      "DELETE": "Excluir card",
      "MOVE": "Mover para etapa",
      "CONTACT_LABEL": "Contato",
      "CONTACT_PLACEHOLDER": "Buscar contato...",
      "TITLE_LABEL": "Título",
      "VALUE_LABEL": "Valor do negócio",
      "NOTES_LABEL": "Observações",
      "LINKED_CONVERSATION": "Conversa vinculada",
      "MOVE_ERROR": "Falha ao mover card. Tente novamente.",
      "API": {
        "CREATE_SUCCESS": "Card adicionado com sucesso.",
        "UPDATE_SUCCESS": "Card atualizado com sucesso.",
        "DELETE_SUCCESS": "Card excluído com sucesso.",
        "ERROR": "Algo deu errado. Tente novamente."
      }
    }
  }
}
```

### Registrar os arquivos de tradução

Verificar onde os arquivos de locale são importados (provavelmente em `app/javascript/dashboard/i18n/index.js`) e adicionar `kanban` em `en` e `pt_BR`.

---

## Verificação

1. Navegar para `/accounts/1/kanban` → ver ícone na sidebar + tela vazia com CTA
2. Criar pipeline "Vendas" com stages: "Lead", "Qualificado", "Proposta", "Ganho"
3. Colunas aparecem na ordem correta com a cor configurada
4. Adicionar card buscando um contato → card aparece na primeira coluna
5. Arrastar card para outra coluna → animação fluida + API PATCH chamada + persiste após refresh
6. Arrastar coluna para reordenar → ordem persiste após refresh
7. Trocar de pipeline no dropdown → board atualiza com stages/items do pipeline selecionado
8. Clicar no card → slide-over abre com detalhes do contato + campos editáveis
9. Testar como agente: pode criar e mover cards mas não vê botão de delete pipeline/stage
10. Testar a API externamente via curl (integração com ferramenta externa)
