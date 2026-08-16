# Task 07 — Fix: `{ deep: true }` desnecessário em 2 watchers do Kanban

Severidade: 🟡 Média. Achado na auditoria de otimização de CRM (2026-08-16).

## Objetivo

Dois componentes do Kanban usam `watch(..., { deep: true })` para sincronizar estado local
com computed vindos da store:

- `KanbanBoard.vue:19-27`:
  ```js
  watch(
    storeStages,
    val => {
      localStages.value = [...val];
    },
    { deep: true }
  );
  ```
- `KanbanColumn.vue:26-34`: mesmo padrão, para `localItems`/`storeItems`.

`storeStages`/`storeItems` são `computed()` que chamam getters Vuex
(`getStagesForPipeline`, `getFilteredSortedItemsForStage`,
`app/javascript/dashboard/store/modules/kanban/getters.js:26-29,59-99`), cuja implementação
**sempre retorna um array novo** (`.map().filter()` / `[...items].sort(...)`). Como a
referência do array já muda a cada recomputação, o watcher já dispara por igualdade
referencial — `deep: true` não adiciona nenhum benefício de disparo, só força o Vue a
percorrer recursivamente todas as propriedades reativas de cada item/stage (inclusive
objetos aninhados como `assignee`, `contact`, `custom_attributes`) só para registrar
dependências que nunca são usadas para decidir se o watcher dispara.

Isso roda a cada mutação Vuex relevante, inclusive nos pushes de ActionCable
(`applyRealtimePipelineItem`, `store/modules/kanban/actions.js:226-242`) — ou seja, em toda
atualização em tempo real de qualquer card, mesmo em colunas não visíveis na tela.

## O que corrigir

Remover `{ deep: true }` dos dois watchers (`KanbanBoard.vue` e `KanbanColumn.vue`). O
watcher continua disparando normalmente (a referência do array muda a cada nova computação
do getter), só sem o custo de percorrer recursivamente cada objeto aninhado.

## Testes

Testar manualmente no Docker local: reordenar stages (`KanbanBoard`) e cards dentro de uma
coluna (`KanbanColumn`), confirmar que a sincronização local/store continua funcionando
(drag-and-drop reflete corretamente, updates em tempo real via ActionCable continuam
aparecendo).

## Critério de pronto

- `deep: true` removido dos dois watchers.
- Drag-and-drop de stages e cards continua funcionando sem regressão visual.
- Updates em tempo real (ActionCable) continuam refletindo no board sem regressão.
- `pnpm eslint:fix` limpo nos arquivos tocados.
