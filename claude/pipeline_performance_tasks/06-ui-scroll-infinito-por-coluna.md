# Task 06 — UI: scroll infinito por coluna e filtros disparando refetch

Severidade: 🟠 Alta. Achado na análise de performance de 2026-09-15.
Depende da task 05.

## Objetivo

`KanbanColumn.vue` renderiza a coluna inteira de uma vez e conta os cards a partir do que está
carregado:

```vue
<span class="...">{{ localItems.length }}</span>          <!-- linha 80 -->
<!-- ... -->
<draggable v-model="localItems" group="kanban-items" item-key="id" ...>
  <template #item="{ element: item }">
    <KanbanCard :item="item" :data-id="item.id" :data-stage-id="stage.id" ... />
  </template>
</draggable>
```

E `KanbanFilterBar`/`KanbanSortMenu` só commitam estado local
(`KanbanSortMenu.vue:47-58` → `store.commit('kanban/SET_KANBAN_SORT', sort)`), porque o filtro
acontecia no getter.

O projeto já tem a peça de scroll infinito pronta: `dashboard/components/IntersectionObserver.vue`
(wrapper de `useIntersectionObserver` do `@vueuse/core`), usado em `ConversationList.vue:86-92`:

```vue
<IntersectionObserver
  v-else
  :options="intersectionObserverOptions"
  @observed="loadMoreConversations"
/>
```

com `options` apontando `root` para o container que rola (`ConversationList.vue:41-44`).

## O que corrigir

1. **`IntersectionObserver` no fim da lista de cada coluna**, dentro do container que rola (o
   `<draggable class="... overflow-y-auto">`, linha 98-107), com `root` apontando para esse
   container — não para `document`, senão colunas fora da viewport horizontal disparam junto.
   `@observed` → `fetchMoreStageItems`.
2. **Badge do cabeçalho** (linha 80) passa a ler `count` do store (total sob os filtros), não
   `localItems.length`. Hoje o número que o agente vê é o total real; depois da paginação,
   manter `localItems.length` faria o badge mostrar "25" numa coluna de 900 cards.
3. **Spinner por coluna** durante `isFetching`, e um estado de fim de lista (o
   `ConversationList.vue:83-85` tem o precedente com `CHAT_LIST.EOF`). Chaves novas de i18n em
   `en/kanban.json` **e** `pt_BR/kanban.json` — o domínio Kanban é a exceção documentada no
   `AGENTS.md` que mantém `pt_BR` sincronizado à mão.
4. **`KanbanFilterBar` e `KanbanSortMenu` passam a disparar refetch** das colunas em vez de só
   commitar estado. Debounce nos campos de texto/range (`KanbanFilterBar.vue`) para não
   disparar um request por tecla. A persistência em `useUISettings`
   (`setKanbanBoardSettings`, `KanbanSortMenu.vue:44-46`) continua igual.
5. **Carga inicial**: `KanbanIndex.vue:61` e `PipelineSelector.vue:16` deixam de chamar
   `fetchItems(pipelineId)` e passam a disparar a página 1 de cada coluna. As stages já estão
   no store nesse ponto (vêm de `fetchPipelines` → `SET_PIPELINES`, `mutations.js:24-39`), então
   dá para disparar em paralelo sem esperar request extra.
6. **⚠️ `position` no drag-and-drop** (risco 2 da visão geral): `onAdd` (`KanbanColumn.vue:32-44`)
   envia `position: newIndex`, o índice **visual**. Com páginas isso é o índice dentro da
   página carregada. Como as páginas são prefixos contíguos ordenados por `position`, somar o
   offset da página resolve — mas "soltar no fim da lista carregada" deixa de significar "fim
   da coluna", então o card pode saltar quando a próxima página carregar. Escolher e
   documentar o comportamento (o mais simples: o card fica onde foi solto dentro da ordem
   global, e a lista se reorganiza ao carregar a próxima página).

## Testes

Docker local, pipeline com mais cards que uma página em pelo menos duas colunas:

1. Rolar uma coluna até o fim: a próxima página carrega sozinha, com spinner, e não duplica
   card. Rolar rápido pra cima e pra baixo no fim da lista não dispara requests concorrentes.
2. Badge do cabeçalho mostra o total real da coluna, não o carregado.
3. Rolar a coluna A não dispara carga da coluna B (`root` correto no observer).
4. Cada filtro e cada ordenação: as colunas resetam para a página 1 e o resultado bate com o
   comportamento anterior (ver task 03, item 3 dos testes — é a mesma validação, feita pela UI).
5. Digitar num campo de filtro com debounce: um request no fim, não um por tecla (aba Network).
6. Arrastar entre colunas paginadas e arrastar dentro da coluna; dar reload e confirmar que a
   ordem persistiu; arrastar na página 2 e confirmar que a página 1 não embaralhou.
7. Tema escuro e tela estreita — o spinner e o estado de fim de lista não podem quebrar o
   layout da coluna.

## Critério de pronto

- Scroll infinito funcionando por coluna, isolado entre colunas.
- Badge = total do servidor.
- Filtros e ordenação disparam refetch, com debounce onde faz sentido, e persistem como hoje.
- Drag-and-drop com `position` correto em qualquer página.
- Chaves de i18n novas em `en/kanban.json` **e** `pt_BR/kanban.json`.
- Só Tailwind, sem CSS customizado/scoped novo (regra do `AGENTS.md`; os dois `<style scoped>`
  existentes em `KanbanColumn.vue:128-132` são de `ghost-class` do vuedraggable e ficam).
- `pnpm eslint` limpo — atenção a `vue/no-bare-strings-in-template: error`.
