# Task 08 — Desmontar o getter global de filtro/ordenação do Kanban

Severidade: 🟠 Alta. Achado na análise de performance de 2026-09-15.
Depende da task 06 (só dá pra remover o filtro do cliente depois que o do servidor estiver
validado lado a lado).

## Objetivo

É a task que corrige o travamento **ao interagir** com o board — diferente das tasks 01-03, que
corrigem o travamento ao **carregar**. Mesmo com paginação, sem esta o board continua engasgando
a cada push de ActionCable.

`app/javascript/dashboard/store/modules/kanban/getters.js:59-99`:

```js
getFilteredSortedItemsForStage:
  ($state, $getters) => (stageId, currentUserId) => {
    let items = $getters.getItemsForStage(stageId);
    // ... 6 filtros encadeados, cada um criando um array novo ...
    const { field, order } = $state.activeSort;
    const dir = order === 'asc' ? 1 : -1;
    return [...items].sort((a, b) => compareByField(a, b, field) * dir);
  },
```

Três problemas somados:

1. **Vuex não cacheia getters method-style.** Um getter que retorna função é reexecutado a
   cada acesso — não há memoização possível, por design.
2. **Retorna sempre um array novo** (`[...items].sort()`), então toda comparação de identidade
   dá "mudou".
3. `KanbanColumn.vue:23-30` o consome num `computed` + `watch`:

```js
const storeItems = computed(() =>
  getFilteredSortedItemsForStage.value(props.stage.id, currentUser.value?.id)
);
const localItems = ref([...storeItems.value]);

watch(storeItems, val => {
  localItems.value = [...val];
});
```

Resultado: **qualquer** mutação no store — um único `pipeline_item.updated` do ActionCable, um
flag de UI, um card criado em outra sessão — invalida o computed de **todas** as colunas, que
re-filtram e re-ordenam (`O(n log n)` por coluna), e como a identidade do array muda sempre, o
`watch` dispara e o `vuedraggable` re-renderiza a coluna inteira. Com centenas de cards e um
board movimentado, isso acontece várias vezes por segundo.

## O que corrigir

Com filtro e ordenação no servidor (task 03) e a lista de ids por coluna vinda do store
(task 05), este getter volta a ser só um mapeamento:

```js
getItemsForStage: $state => stageId =>
  ($state.stageItems[stageId]?.ids || []).map(id => $state.items[id]).filter(Boolean),
```

1. Remover `getFilteredSortedItemsForStage` e os helpers que só ele usa (`isWithinRange`
   linhas 3-9, `compareByField` linhas 11-17).
2. `isFilterActive` / `isBoardFiltered` / `isSortActive` (linhas 42-57) continuam necessários
   para a UI (rótulo do botão de filtro, e `KanbanColumn.vue:48` usa `isSortActive` para
   decidir se o arrasto reordena) — manter, são baratos. **Atenção:** com a ordem padrão
   virando `position` (decisão da task 03), a lógica de `isSortActive` muda de referência —
   `DEFAULT_KANBAN_SORT` em `constants.js:9-12` passa a ser `{ field: 'position', order: 'asc' }`,
   e a condição de `KanbanColumn.vue:46-51` que hoje cancela o reorder precisa ser revista
   (com `position` ativo o arrasto **deve** reordenar).
3. Atualizar `store/modules/kanban/specs/getters.spec.js` — ele mocka `getItemsForStage`
   (linha 25) e testa o getter que está sendo removido.
4. Conferir se `localItems`/`watch` em `KanbanColumn.vue` ainda precisam existir: a cópia local
   existe porque o `vuedraggable` faz `v-model` na lista. Provavelmente sim, mas com a
   identidade do array estável o `watch` deixa de disparar à toa.

## Testes

Docker local, pipeline com várias centenas de cards carregados em pelo menos duas colunas:

1. **Medição de render** (Vue DevTools ou Performance do navegador): com o board aberto, mover
   um card em outra sessão e observar quantos componentes re-renderizam. Antes: todas as
   colunas. Critério: só a(s) coluna(s) afetada(s).
2. Interagir com o board (abrir card, aplicar filtro, arrastar) com o CPU throttling ligado no
   DevTools e confirmar que não há travamento perceptível.
3. Filtros e ordenação continuam dando o mesmo resultado (agora vindo do servidor) — é a mesma
   validação da task 06, refeita depois da remoção do código client-side.
4. `pnpm test` — `store/modules/kanban/specs/` tem que passar.

## Critério de pronto

- `getFilteredSortedItemsForStage` e seus helpers removidos.
- `DEFAULT_KANBAN_SORT` alinhado com a decisão de ordem padrão (`position`), e o cancelamento
  de reorder em `KanbanColumn.vue:46-51` revisto — arrastar para reordenar tem que funcionar.
- Uma mutação no store não re-renderiza colunas não afetadas.
- Specs do módulo kanban passando (`pnpm test`).
- `pnpm eslint` limpo.
