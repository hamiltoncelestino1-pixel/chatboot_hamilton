# Task 05 — Store Vuex: estado de paginação por stage

Severidade: 🟠 Alta. Achado na análise de performance de 2026-09-15.
Depende da task 03 (consome o contrato novo da API).

## Objetivo

O módulo `app/javascript/dashboard/store/modules/kanban/` assume "tudo carregado de uma vez".
`actions.js:19-27`:

```js
fetchItems: async ({ commit }, pipelineId) => {
  commit('SET_KANBAN_UI_FLAG', { isFetchingItems: true });
  try {
    const { data } = await PipelinesAPI.getItems(pipelineId);
    commit('SET_ITEMS', data);
  } finally {
    commit('SET_KANBAN_UI_FLAG', { isFetchingItems: false });
  }
},
```

Um request, todos os cards, um flag de UI global (`index.js:17-24`), e `itemOrder[stageId]`
como um array simples de ids (`mutations.js:97-106`).

## O que corrigir

### 1. Estado por stage

Trocar `itemOrder: {}` por um registro por stage, algo como:

```js
stageItems: {},   // { [stageId]: { ids: [], page: 1, hasMore: true, count: 0, isFetching: false } }
```

`count` vem de `meta.count` da task 03 (total sob os filtros ativos) e é a fonte tanto do badge
do cabeçalho quanto do `hasMore` (`ids.length < count`). `isFetching` passa a ser por coluna —
o flag global `isFetchingItems` deixa de fazer sentido quando 6 colunas carregam em paralelo.

### 2. Ações

- `fetchStageItems({ pipelineId, stageId })` — página 1, substitui a lista da coluna.
- `fetchMoreStageItems({ pipelineId, stageId })` — próxima página, **append**; no-op se
  `!hasMore` ou `isFetching` (o `IntersectionObserver` da task 06 dispara mais de uma vez).
- `resetBoard()` / refetch de todas as colunas ao mudar filtro, sort ou pipeline ativo.

`fetchItems` (pipeline inteiro) deixa de existir no board. Seus dois chamadores
(`KanbanIndex.vue:61` e `PipelineSelector.vue:16`) passam a disparar a carga das colunas —
ver task 06.

Os filtros e o sort ativos (`state.activeFilters`, `state.activeSort`, `state.showOnlyMine`)
passam a ser serializados como params da API, não aplicados no getter.

### 3. ⚠️ ActionCable (risco alto)

`applyRealtimePipelineItem` (`actions.js:253-269`) hoje faz `SET_ITEM`, e `SET_ITEM`
(`mutations.js:108-115`) **anexa o id ao fim de `itemOrder`**:

```js
SET_ITEM($state, item) {
  $state.items[item.id] = item;
  const stageId = item.pipeline_stage_id;
  const order = $state.itemOrder[stageId] || [];
  if (!order.includes(item.id)) {
    $state.itemOrder[stageId] = [...order, item.id];
  }
},
```

Com paginação isso está errado: um card que pertence à página 5 apareceria no fim da página 1,
e `count` ficaria dessincronizado do servidor. Decidir explicitamente e deixar comentado no
código (o módulo já tem esse hábito, ver o comentário de `actions.js:249-252`):

- item **já carregado** → atualiza em `items` normalmente; se mudou de stage, `MOVE_ITEM` entre
  as listas carregadas e ajusta os dois `count`;
- item **não carregado** (criado por outra sessão, ou fora da página) → **não inserir na lista**;
  só incrementar o `count` da coluna de destino. O card aparece quando o agente rolar até ele.
- item que sai da coluna por causa de um filtro ativo → remover da lista e decrementar `count`.

Esse é o ponto mais fácil de introduzir duplicata ou contador errado. Testar com duas sessões.

### 4. Outras ações afetadas

- `moveItem` (`actions.js:149-187`) — `position` passa a precisar do offset da página
  (ver risco 2 da visão geral) e os `count` das duas colunas mudam.
- `reorderItems` (`:198-205`) — passa `start_position` para a API (task 03).
- `deleteItem` (`:128-140`) e `exportItem` (`:219-235`) — decrementar `count`.
- `createItem` (`:99-113`) — incrementar `count`.

## Testes

Docker local, pipeline com mais cards que uma página em pelo menos duas colunas:

1. Abrir o board: cada coluna carrega sua página 1; `count` bate com o total real.
2. Rolar uma coluna até o fim: página 2 carrega e faz append, sem duplicar card nenhum.
3. Trocar filtro, sort e pipeline: todas as colunas resetam para a página 1 com os
   parâmetros novos.
4. **Duas sessões abertas no mesmo board:** mover um card numa e confirmar na outra; criar um
   card que caia fora da página carregada e confirmar que o contador sobe **sem** aparecer
   card duplicado ou fantasma na lista; apagar um card e confirmar o decremento.
5. Disparar o `IntersectionObserver` várias vezes seguidas (rolar rápido pra cima e pra baixo
   no fim da lista) e confirmar que não dispara requests concorrentes duplicados.

## Critério de pronto

- Estado de paginação por coluna, com `count` vindo do servidor.
- `fetchMoreStageItems` idempotente contra disparos repetidos e respeitando `hasMore`.
- Nenhum card duplicado, fantasma ou contador dessincronizado em cenário de duas sessões.
- Comportamento do ActionCable documentado em comentário no código, não implícito.
- `pnpm eslint` limpo (o script ignora argumento de arquivo e linta a árvore toda — é esperado).
