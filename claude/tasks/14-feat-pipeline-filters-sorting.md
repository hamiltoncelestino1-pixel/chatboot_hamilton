# Task: Filtros Avançados e Ordenação de Oportunidades

## Objetivo

O board Kanban hoje não tem nenhum filtro ou ordenação — `pipeline_items_controller.rb#index` só
suporta `?stage_id=`. Esta task adiciona filtro por responsável, time, etiqueta e faixa de valor,
além de ordenação, tanto no backend quanto numa barra de filtros no board.

**Decisão de design:** não reaproveitar o motor genérico de `CustomFilter`
(`app/models/custom_filter.rb`, `app/services/filters/*`), que é fortemente acoplado a
`conversations`/`contacts` (`filter_config[:table_name]`, services próprios por entidade) —
desproporcional ao domínio de `PipelineItem`, que tem poucos atributos filtráveis. Em vez disso,
um **finder dedicado**, no espírito do hash `SORT_OPTIONS` já usado em
`app/finders/conversation_finder.rb`.

**Pré-requisitos:** tasks 08 (assignee/team) e 10 (labels exclusivas) implementadas — os filtros
dependem desses campos existirem em `PipelineItem`.

---

## 1. Finder novo — `app/finders/pipeline_item_finder.rb`

```ruby
class PipelineItemFinder
  SORT_OPTIONS = {
    'created_at_asc' => %w[created_at asc],
    'created_at_desc' => %w[created_at desc],
    'value_asc' => %w[value asc],
    'value_desc' => %w[value desc],
    'position_asc' => %w[position asc],
  }.with_indifferent_access.freeze

  def initialize(pipeline:, params:)
    @pipeline = pipeline
    @params = params
  end

  def perform
    items = base_scope
    items = filter_by_stage(items)
    items = filter_by_assignee(items)
    items = filter_by_team(items)
    items = filter_by_label(items)
    items = filter_by_value_range(items)
    sort(items)
  end

  private

  def base_scope
    @pipeline.pipeline_items.includes(:contact, :conversation, :assignee, :team, :pipeline_stage)
  end

  def filter_by_stage(items)
    return items if @params[:stage_id].blank?

    items.where(pipeline_stage_id: @params[:stage_id])
  end

  def filter_by_assignee(items)
    return items if @params[:assignee_id].blank?

    items.where(assignee_id: @params[:assignee_id])
  end

  def filter_by_team(items)
    return items if @params[:team_id].blank?

    items.where(team_id: @params[:team_id])
  end

  def filter_by_label(items)
    return items if @params[:label].blank?

    items.tagged_with(@params[:label])
  end

  def filter_by_value_range(items)
    items = items.where('value >= ?', @params[:min_value]) if @params[:min_value].present?
    items = items.where('value <= ?', @params[:max_value]) if @params[:max_value].present?
    items
  end

  def sort(items)
    column, direction = SORT_OPTIONS[@params[:sort_by]] || %w[position asc]
    items.reorder(column => direction)
  end
end
```

`tagged_with` é o método da gem `acts-as-taggable-on` (já usada via `Labelable`, task 10) — só
funciona se a task 10 já tiver sido aplicada (senão, remover `filter_by_label` desta versão).

---

## 2. `app/controllers/api/v1/accounts/pipeline_items_controller.rb`

Trocar o `index` atual (que só filtra por `stage_id` manualmente) para usar o finder:

```ruby
def index
  @items = PipelineItemFinder.new(pipeline: @pipeline, params: params).perform
end
```

Query params suportados: `stage_id` (retrocompatível), `assignee_id`, `team_id`, `label`,
`min_value`, `max_value`, `sort_by`.

---

## 3. Frontend — `KanbanFilterBar.vue`

Não reaproveitar `ConditionRow.vue`/`ConversationFilter.vue` inteiros (desenhados para o motor de
`CustomFilter` persistido — API e formato de dados diferentes). Componente novo, mais simples:

`app/javascript/dashboard/routes/dashboard/kanban/components/KanbanFilterBar.vue`:

```vue
<script setup>
import { computed, reactive, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';

const props = defineProps({
  pipelineId: { type: Number, required: true },
});
const emit = defineEmits(['change']);

const { t } = useI18n();
const getPipelineMembers = useMapGetter('pipelineMembers/getPipelineMembers');
const teams = useMapGetter('teams/getTeams');
const pipelineLabels = useMapGetter('labels/getPipelineLabels');

const members = computed(() => getPipelineMembers.value(props.pipelineId));

const filters = reactive({
  assignee_id: '',
  team_id: '',
  label: '',
  min_value: '',
  max_value: '',
  sort_by: 'position_asc',
});

watch(
  filters,
  value => emit('change', { ...value }),
  { deep: true }
);

const sortOptions = [
  { value: 'position_asc', label: t('KANBAN.FILTERS.SORT_OPTIONS.POSITION') },
  { value: 'created_at_desc', label: t('KANBAN.FILTERS.SORT_OPTIONS.NEWEST') },
  { value: 'created_at_asc', label: t('KANBAN.FILTERS.SORT_OPTIONS.OLDEST') },
  { value: 'value_desc', label: t('KANBAN.FILTERS.SORT_OPTIONS.VALUE_DESC') },
  { value: 'value_asc', label: t('KANBAN.FILTERS.SORT_OPTIONS.VALUE_ASC') },
];
</script>

<template>
  <div class="flex flex-wrap items-center gap-2 px-4 py-2 border-b border-slate-100 dark:border-slate-800">
    <select v-model="filters.assignee_id" class="text-xs px-2 py-1.5 border border-slate-200 dark:border-slate-600 rounded-lg bg-white dark:bg-slate-700">
      <option value="">{{ t('KANBAN.FILTERS.ASSIGNEE') }}</option>
      <option v-for="agent in members" :key="agent.id" :value="agent.id">{{ agent.name }}</option>
    </select>

    <select v-model="filters.team_id" class="text-xs px-2 py-1.5 border border-slate-200 dark:border-slate-600 rounded-lg bg-white dark:bg-slate-700">
      <option value="">{{ t('KANBAN.FILTERS.TEAM') }}</option>
      <option v-for="team in teams" :key="team.id" :value="team.id">{{ team.name }}</option>
    </select>

    <select v-model="filters.label" class="text-xs px-2 py-1.5 border border-slate-200 dark:border-slate-600 rounded-lg bg-white dark:bg-slate-700">
      <option value="">{{ t('KANBAN.FILTERS.LABEL') }}</option>
      <option v-for="label in pipelineLabels" :key="label.id" :value="label.title">{{ label.title }}</option>
    </select>

    <input v-model="filters.min_value" type="number" class="w-20 text-xs px-2 py-1.5 border border-slate-200 dark:border-slate-600 rounded-lg bg-white dark:bg-slate-700" :placeholder="t('KANBAN.FILTERS.VALUE_MIN')" />
    <input v-model="filters.max_value" type="number" class="w-20 text-xs px-2 py-1.5 border border-slate-200 dark:border-slate-600 rounded-lg bg-white dark:bg-slate-700" :placeholder="t('KANBAN.FILTERS.VALUE_MAX')" />

    <select v-model="filters.sort_by" class="text-xs px-2 py-1.5 border border-slate-200 dark:border-slate-600 rounded-lg bg-white dark:bg-slate-700 ml-auto">
      <option v-for="opt in sortOptions" :key="opt.value" :value="opt.value">{{ opt.label }}</option>
    </select>
  </div>
</template>
```

### `store/modules/kanban/actions.js` — `fetchItems` aceita filtros

```javascript
fetchItems: async ({ commit }, { pipelineId, filters = {} }) => {
  commit('SET_KANBAN_UI_FLAG', { isFetchingItems: true });
  try {
    const { data } = await PipelinesAPI.getItems(pipelineId, filters);
    commit('CLEAR_ITEMS_FOR_PIPELINE', pipelineId); // nova mutation, ver abaixo
    commit('SET_ITEMS', data);
  } finally {
    commit('SET_KANBAN_UI_FLAG', { isFetchingItems: false });
  }
},
```

Isso muda a assinatura de `fetchItems` (hoje recebe só `pipelineId` como payload direto) — ajustar
todas as chamadas existentes (`KanbanIndex.vue`, `AddPipelineModal.vue`/`AddPipeline.vue`,
`PipelineSelector.vue`) para `store.dispatch('kanban/fetchItems', { pipelineId })` (sem filtros =
comportamento atual preservado).

Adicionar mutation `CLEAR_ITEMS_FOR_PIPELINE` em `mutations.js` para limpar `itemOrder` das etapas
do pipeline antes de aplicar um novo filtro (evita cards "fantasmas" de um filtro anterior que não
batem mais com o novo resultado):

```javascript
CLEAR_ITEMS_FOR_PIPELINE($state, pipelineId) {
  const stageIds = $state.stageOrder[pipelineId] || [];
  stageIds.forEach(stageId => { $state.itemOrder[stageId] = []; });
},
```

### `api/pipelines.js#getItems`

Trocar a assinatura atual (`getItems(pipelineId, stageId = null)`, que monta a query string na
mão) para aceitar um objeto de params genérico:

```javascript
getItems(pipelineId, params = {}) {
  return axios.get(`${this.url}/${pipelineId}/pipeline_items`, { params });
}
```

### `pages/KanbanIndex.vue`

Adicionar estado de filtros reativo e re-fetch ao mudar:

```javascript
import KanbanFilterBar from '../components/KanbanFilterBar.vue';

const activeFilters = ref({});
const handleFilterChange = async filters => {
  activeFilters.value = filters;
  await store.dispatch('kanban/fetchItems', {
    pipelineId: activePipeline.value.id,
    filters,
  });
};
```

```html
<KanbanFilterBar
  v-if="activePipeline"
  :pipeline-id="activePipeline.id"
  @change="handleFilterChange"
/>
```

---

## i18n

`en/kanban.json` (novo bloco `KANBAN.FILTERS`):
```json
"FILTERS": {
  "ASSIGNEE": "Assignee",
  "TEAM": "Team",
  "LABEL": "Label",
  "VALUE_MIN": "Min value",
  "VALUE_MAX": "Max value",
  "SORT_OPTIONS": {
    "POSITION": "Manual order",
    "NEWEST": "Newest first",
    "OLDEST": "Oldest first",
    "VALUE_DESC": "Highest value",
    "VALUE_ASC": "Lowest value"
  }
}
```

`pt_BR/kanban.json`:
```json
"FILTERS": {
  "ASSIGNEE": "Responsável",
  "TEAM": "Time",
  "LABEL": "Etiqueta",
  "VALUE_MIN": "Valor mín.",
  "VALUE_MAX": "Valor máx.",
  "SORT_OPTIONS": {
    "POSITION": "Ordem manual",
    "NEWEST": "Mais recentes",
    "OLDEST": "Mais antigos",
    "VALUE_DESC": "Maior valor",
    "VALUE_ASC": "Menor valor"
  }
}
```

---

## Verificação

1. No board, filtrar por um agente específico — só mostra oportunidades atribuídas a ele.
2. Filtrar por time, por etiqueta, por faixa de valor — combináveis (todos os filtros aplicados em
   conjunto, AND).
3. Trocar ordenação para "Maior valor" — cards reordenam dentro de cada coluna por `value desc`.
4. Limpar todos os filtros — volta para `position asc` (ordem manual de drag-and-drop).
5. Confirmar que agente sem acesso ao pipeline não consegue usar `?assignee_id=` para vazar dados
   de outro pipeline (o `fetch_pipeline` já usa `policy_scope`, da task 08 — o finder opera sempre
   dentro de `@pipeline.pipeline_items`, escopado).
6. Testar via curl: `GET /pipelines/1/pipeline_items?assignee_id=5&sort_by=value_desc`.
