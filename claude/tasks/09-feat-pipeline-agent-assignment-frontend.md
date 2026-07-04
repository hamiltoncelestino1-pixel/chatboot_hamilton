# Task: Atribuição de Agentes a Pipelines e Oportunidades — Frontend

## Objetivo

Consumir a API criada na task `08-feat-pipeline-agent-assignment-backend.md`:

1. Store + API client para gerenciar membros de um pipeline (usado pela aba "Agentes" da task
   `12-feat-pipeline-settings-page.md`).
2. Seletor de assignee + team no card de oportunidade (`KanbanCardDetail.vue`), mirror exato do
   bloco de assignee/team de `app/javascript/dashboard/routes/dashboard/conversation/ConversationAction.vue`.
3. Esconder pipelines/entrada de sidebar para agentes sem nenhum pipeline atribuído (o backend já
   filtra a lista — aqui é só UX).

**Pré-requisito:** Task 08 implementada (API disponível).

---

## 1. API Client — `app/javascript/dashboard/api/pipelineMembers.js`

Mirror exato de `app/javascript/dashboard/api/teams.js` (métodos `getAgents`/`addAgents`/
`updateAgents`), adaptado para pipeline:

```javascript
/* global axios */
import ApiClient from './ApiClient';

class PipelineMembersAPI extends ApiClient {
  constructor() {
    super('pipelines', { accountScoped: true });
  }

  get(pipelineId) {
    return axios.get(`${this.url}/${pipelineId}/pipeline_members`);
  }

  create({ pipelineId, agentIds }) {
    return axios.post(`${this.url}/${pipelineId}/pipeline_members`, {
      user_ids: agentIds,
    });
  }

  update({ pipelineId, agentIds }) {
    return axios.patch(`${this.url}/${pipelineId}/pipeline_members`, {
      user_ids: agentIds,
    });
  }
}

export default new PipelineMembersAPI();
```

---

## 2. Store novo — `app/javascript/dashboard/store/modules/pipelineMembers.js`

Mirror exato de `app/javascript/dashboard/store/modules/teamMembers.js` (arquivo único, não pasta
com 4 arquivos):

```javascript
import PipelineMembersAPI from '../../api/pipelineMembers';

export const SET_PIPELINE_MEMBERS_UI_FLAG = 'SET_PIPELINE_MEMBERS_UI_FLAG';
export const SET_PIPELINE_MEMBERS = 'SET_PIPELINE_MEMBERS';

export const state = {
  records: {},
  uiFlags: {
    isFetching: false,
    isCreating: false,
    isUpdating: false,
  },
};

export const getters = {
  getUIFlags(_state) {
    return _state.uiFlags;
  },
  getPipelineMembers: $state => pipelineId => {
    return $state.records[pipelineId] || [];
  },
};

export const actions = {
  get: async ({ commit }, { pipelineId }) => {
    commit(SET_PIPELINE_MEMBERS_UI_FLAG, { isFetching: true });
    try {
      const { data } = await PipelineMembersAPI.get(pipelineId);
      commit(SET_PIPELINE_MEMBERS, { pipelineId, data });
    } finally {
      commit(SET_PIPELINE_MEMBERS_UI_FLAG, { isFetching: false });
    }
  },
  create: async ({ commit }, { pipelineId, agentIds }) => {
    commit(SET_PIPELINE_MEMBERS_UI_FLAG, { isCreating: true });
    try {
      const { data } = await PipelineMembersAPI.create({ pipelineId, agentIds });
      commit(SET_PIPELINE_MEMBERS, { pipelineId, data });
    } finally {
      commit(SET_PIPELINE_MEMBERS_UI_FLAG, { isCreating: false });
    }
  },
  update: async ({ commit }, { pipelineId, agentIds }) => {
    commit(SET_PIPELINE_MEMBERS_UI_FLAG, { isUpdating: true });
    try {
      const { data } = await PipelineMembersAPI.update({ pipelineId, agentIds });
      commit(SET_PIPELINE_MEMBERS, { pipelineId, data });
    } finally {
      commit(SET_PIPELINE_MEMBERS_UI_FLAG, { isUpdating: false });
    }
  },
};

export const mutations = {
  [SET_PIPELINE_MEMBERS_UI_FLAG]($state, data) {
    $state.uiFlags = { ...$state.uiFlags, ...data };
  },
  [SET_PIPELINE_MEMBERS]($state, { pipelineId, data }) {
    $state.records = { ...$state.records, [pipelineId]: data };
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

### Registrar em `app/javascript/dashboard/store/index.js`

```javascript
import pipelineMembers from './modules/pipelineMembers';
// ...
modules: {
  // ...
  pipelineMembers,
}
```

---

## 3. Seletor de assignee/team no card — alterações em `KanbanCardDetail.vue`

Arquivo atual (`app/javascript/dashboard/routes/dashboard/kanban/components/KanbanCardDetail.vue`)
usa `<script setup>` com `ref`/`computed`/`watch` puro (sem `MultiselectDropdown` ainda). Adicionar,
seguindo o padrão real de `ConversationAction.vue` (que usa `MultiselectDropdown` de
`shared/components/ui/MultiselectDropdown.vue` para assignee e team):

```vue
<script setup>
import { ref, computed, watch, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import MultiselectDropdown from 'shared/components/ui/MultiselectDropdown.vue';

const props = defineProps({
  item: { type: Object, default: null },
});
const emit = defineEmits(['close']);

const { t } = useI18n();
const store = useStore();
const activePipeline = useMapGetter('kanban/getActivePipeline');
const getStagesForPipeline = useMapGetter('kanban/getStagesForPipeline');
const getPipelineMembers = useMapGetter('pipelineMembers/getPipelineMembers');
const uiFlags = useMapGetter('kanban/getUIFlags');

const teams = useMapGetter('teams/getTeams');

const stages = computed(() =>
  activePipeline.value ? getStagesForPipeline.value(activePipeline.value.id) : []
);

// Só agentes membros do pipeline ativo podem ser assignee (regra validada também no backend)
const assignableAgents = computed(() =>
  activePipeline.value ? getPipelineMembers.value(activePipeline.value.id) : []
);

const assignee = ref(null);
const team = ref(null);

watch(
  () => props.item,
  item => {
    if (item) {
      assignee.value = item.assignee || null;
      team.value = item.team || null;
    }
  },
  { immediate: true }
);

onMounted(() => {
  if (activePipeline.value) {
    store.dispatch('pipelineMembers/get', { pipelineId: activePipeline.value.id });
  }
  store.dispatch('teams/get');
});

const onAssignAgent = async selected => {
  const assigneeId = selected?.id || null;
  try {
    await store.dispatch('kanban/updateItem', { id: props.item.id, assignee_id: assigneeId });
    assignee.value = selected;
  } catch {
    useAlert(t('KANBAN.ITEM.ERRORS.ASSIGNEE_NOT_MEMBER'));
  }
};

const onAssignTeam = async selected => {
  const teamId = selected?.id || null;
  await store.dispatch('kanban/updateItem', { id: props.item.id, team_id: teamId });
  team.value = selected;
};
</script>
```

E no template, dentro do bloco de detalhes (após o bloco de contato, antes de `title`/`value`):

```html
<div>
  <label class="block text-xs font-medium text-slate-600 dark:text-slate-400 mb-1">
    {{ t('KANBAN.ITEM.ASSIGNEE_LABEL') }}
  </label>
  <MultiselectDropdown
    :options="assignableAgents"
    :selected-item="assignee"
    :multiselector-title="t('AGENT_MGMT.MULTI_SELECTOR.TITLE.AGENT')"
    :multiselector-placeholder="t('KANBAN.ITEM.ASSIGNEE_PLACEHOLDER')"
    :no-search-result="t('AGENT_MGMT.MULTI_SELECTOR.SEARCH.NO_RESULTS.AGENT')"
    :input-placeholder="t('AGENT_MGMT.MULTI_SELECTOR.SEARCH.PLACEHOLDER.AGENT')"
    @select="onAssignAgent"
  />
</div>

<div>
  <label class="block text-xs font-medium text-slate-600 dark:text-slate-400 mb-1">
    {{ t('KANBAN.ITEM.TEAM_LABEL') }}
  </label>
  <MultiselectDropdown
    :options="teams"
    :selected-item="team"
    :multiselector-title="t('AGENT_MGMT.MULTI_SELECTOR.TITLE.TEAM')"
    :multiselector-placeholder="t('KANBAN.ITEM.TEAM_PLACEHOLDER')"
    :no-search-result="t('AGENT_MGMT.MULTI_SELECTOR.SEARCH.NO_RESULTS.TEAM')"
    :input-placeholder="t('AGENT_MGMT.MULTI_SELECTOR.SEARCH.PLACEHOLDER.TEAM')"
    @select="onAssignTeam"
  />
</div>
```

`assignableAgents` já é filtrada pela lista de membros do pipeline (não pela lista geral de
agentes da conta) — reforça no frontend a mesma regra que o backend valida.

---

## 4. Avatar do assignee no card — `KanbanCard.vue`

Adicionar um pequeno indicador do responsável no rodapé do card (arquivo atual não tem isso):

```html
<div class="flex items-center justify-between mt-2">
  <span v-if="formattedValue" class="text-xs font-semibold text-emerald-600 dark:text-emerald-400">
    {{ formattedValue }}
  </span>
  <img
    v-if="item.assignee?.thumbnail"
    :src="item.assignee.thumbnail"
    :title="item.assignee.name"
    class="w-5 h-5 rounded-full object-cover ml-auto"
  />
  <span
    v-else-if="item.assignee"
    :title="item.assignee.name"
    class="w-5 h-5 rounded-full bg-slate-200 dark:bg-slate-600 flex items-center justify-center text-[10px] font-semibold text-slate-600 dark:text-slate-200 ml-auto"
  >
    {{ item.assignee.name?.[0]?.toUpperCase() }}
  </span>
</div>
```

(Confirmar o nome exato do campo de avatar retornado pelo partial `_agent.json.jbuilder` —
provavelmente `thumbnail` ou `avatar_url`, igual ao usado em outros lugares do dashboard para
agentes.)

---

## 5. Esconder Kanban/pipelines sem atribuição

### `app/javascript/dashboard/components-next/sidebar/Sidebar.vue`

A entrada atual (linha ~464-470) é fixa, sem condição:

```javascript
{
  name: 'Kanban',
  label: t('SIDEBAR.KANBAN'),
  icon: 'i-lucide-columns-3',
  to: accountScopedRoute('kanban_index'),
  activeOn: ['kanban_index'],
},
```

Como o backend (`policy_scope`) já filtra `GET /pipelines`, a store `kanban` só recebe pipelines
permitidos. Adicionar um getter dedicado no store `kanban` (`getters.js`):

```javascript
hasAnyPipeline: state => state.pipelineOrder.length > 0,
```

E no `Sidebar.vue`, seguir o mesmo padrão condicional já usado para a entrada "Settings Agent
Assignment" (`...(hasAdvancedAssignment.value ? [...] : [])`), mas para isso a lista de pipelines
precisa já ter sido buscada antes do sidebar renderizar — como isso pode não ser garantido em todo
carregamento, a alternativa mais simples e robusta é **não esconder a entrada do menu**, e deixar
que `KanbanIndex.vue` mostre o `KanbanEmptyState.vue` já existente quando `pipelines.length === 0`
(componente já trata esse caso). Portanto, **nenhuma mudança no `Sidebar.vue` é estritamente
necessária** — documentar essa decisão e não implementar o esconder condicional, para evitar
condição de corrida entre fetch de pipelines e render do menu.

---

## i18n

`app/javascript/dashboard/i18n/locale/en/kanban.json` — adicionar em `KANBAN.ITEM`:

```json
"ASSIGNEE_LABEL": "Assignee",
"ASSIGNEE_PLACEHOLDER": "Assign an agent",
"TEAM_LABEL": "Team",
"TEAM_PLACEHOLDER": "Assign a team",
"UNASSIGNED": "Unassigned",
"ERRORS": {
  "ASSIGNEE_NOT_MEMBER": "This agent is not a member of the pipeline."
}
```

`app/javascript/dashboard/i18n/locale/pt_BR/kanban.json`:

```json
"ASSIGNEE_LABEL": "Responsável",
"ASSIGNEE_PLACEHOLDER": "Atribuir um agente",
"TEAM_LABEL": "Time",
"TEAM_PLACEHOLDER": "Atribuir um time",
"UNASSIGNED": "Não atribuído",
"ERRORS": {
  "ASSIGNEE_NOT_MEMBER": "Este agente não é membro do pipeline."
}
```

---

## Verificação

1. Como admin, em Configurações > Pipelines > aba Agentes (task 12), adicionar 2 agentes ao
   pipeline "Vendas".
2. Ir no board Kanban, abrir uma oportunidade — o dropdown de "Responsável" deve listar **só** os
   2 agentes adicionados (não todos os agentes da conta).
3. Atribuir um responsável — persiste após reload; card mostra o avatar.
4. Atribuir um time (lista todos os times, sem restrição) — persiste.
5. Tentar forçar via API (curl) um `assignee_id` de agente fora do pipeline — 422, e a UI deve
   mostrar `KANBAN.ITEM.ERRORS.ASSIGNEE_NOT_MEMBER` se essa chamada partir de um fluxo de UI.
6. Logar como agente sem nenhum pipeline atribuído — `/accounts/:id/kanban` mostra o
   `KanbanEmptyState.vue` (nenhum pipeline retornado pela API).
