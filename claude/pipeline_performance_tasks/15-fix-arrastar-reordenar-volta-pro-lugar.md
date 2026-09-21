# Task 15 — Fix: arrastar para reordenar dentro da coluna ainda volta pro lugar

Severidade: 🔴 Crítico. Achado na revisão de 2026-09-16 (auditoria da implementação das tasks 01-07).

**Status: resolvido em 2026-09-16 como efeito colateral da [task 08](08-desmontar-getter-global.md)**
(saída 1, a preferida). Com `getFilteredSortedItemsForStage` removido, `KanbanColumn.vue` consome
`getItemsForStage` direto — não há mais reordenação client-side por cima do `REORDER_ITEMS`, então
o card não volta mais pro lugar depois do arrasto. Validado manualmente no Docker local.

## Objetivo

Este é o bug que a decisão de produto da task 03 ("ordem padrão passa a ser `position`")
prometia corrigir. **Metade foi implementada, e o efeito visível continua igual.**

O que ficou certo: `DEFAULT_KANBAN_SORT` agora é `{ field: 'position', order: 'asc' }`
(`constants.js:9-13`), então `isSortActive` é `false` no estado padrão e o `onEnd` de
`KanbanColumn.vue:74-85` **realmente dispara** o `reorderItems`, e o backend persiste as
posições corretamente.

O que faltou: o board continua reordenando no cliente por cima disso.

```js
// getters.js:166-175 - ainda ordena o que já está carregado
getFilteredSortedItemsForStage:
  ($state, $getters) => (stageId, currentUserId) => {
    const items = $getters.getItemsForStage(stageId)
      .filter(i => itemMatchesActiveFilters($state, i, currentUserId));
    const { field, order } = $state.activeSort;
    const dir = order === 'asc' ? 1 : -1;
    return [...items].sort((a, b) => compareByField(a, b, field) * dir);
  },
```

```js
// mutations.js:249-252 - só troca a ordem dos ids, não mexe em item.position
REORDER_ITEMS($state, { stageId, orderedIds }) {
  const existing = $state.stageItems[stageId] || emptyStageItemsState();
  $state.stageItems[stageId] = { ...existing, ids: orderedIds };
},
```

Sequência do bug, com a coluna A(pos 0), B(pos 1), C(pos 2) e o agente arrastando C pro topo:

1. `vuedraggable` atualiza `localItems` = `[C, A, B]` (v-model).
2. `onEnd` despacha `reorderItems` → `REORDER_ITEMS` → `stageItems[id].ids = [C, A, B]`.
3. `storeItems` (`KanbanColumn.vue:30-32`) recomputa: `getItemsForStage` devolve `[C, A, B]`,
   e o `.sort()` reordena por `a.position - b.position` usando as posições **antigas** (o store
   ainda tem C.position = 2) → volta a `[A, B, C]`.
4. `watch(storeItems)` (`KanbanColumn.vue:35-37`) dispara → `localItems = [A, B, C]` → **o card
   volta pro lugar na cara do agente**.

O mais confuso pro usuário: o banco ficou certo. Dando F5 o card aparece na posição nova,
porque a API devolve ordenado por `position`. Ou seja, "funciona, mas parece que não funcionou".

## O que corrigir

Duas saídas, em ordem de preferência:

1. **Executar a task 08 agora** ([08-desmontar-getter-global.md](08-desmontar-getter-global.md)).
   Ela remove o filtro/ordenação client-side de vez — o board passa a confiar na ordem que o
   servidor devolveu, e este bug deixa de existir por construção. É a solução certa, e a task 08
   já estava planejada logo depois da 06; o bug é consequência direta de a 08 ainda não ter sido
   feita. Resolve de quebra a divergência da task 17 (`only_mine` + `assignee_id`) e o custo de
   re-render descrito na própria 08.

2. **Se a task 08 for ficar pra depois**, fazer o fix mínimo: `REORDER_ITEMS` passa a reescrever
   `position` de cada item em `$state.items` conforme o novo índice (espelhando o que o backend
   grava com `start_position + index`), para que o `.sort()` client-side chegue ao mesmo
   resultado em vez de desfazer o arrasto. É um paliativo: mantém duas fontes de verdade para a
   ordem, que é exatamente o que a task 08 elimina.

Escolher uma e anotar aqui qual foi — não fazer as duas.

## Testes

1. Coluna com 3+ cards, ordenação no padrão (ordem manual): arrastar um card do fim pro topo e
   confirmar que **ele fica lá**, sem reload.
2. Recarregar a página e confirmar que a ordem persistiu (valida que o backend continua certo).
3. Arrastar um card em uma coluna que já carregou mais de uma página e confirmar que a página 1
   não embaralhou depois do reload (interage com o `start_position`, task 03).
4. Com uma ordenação explícita ativa (ex. "Valor"), arrastar dentro da coluna e confirmar que o
   comportamento continua sendo o de hoje: o arrasto é cancelado e a lista volta ao sort
   (`KanbanColumn.vue:76-79`).
5. Arrastar entre colunas continua funcionando nos dois casos.
6. `pnpm test` — os specs de `store/modules/kanban/specs/` precisam continuar passando (e, se a
   saída 1 for escolhida, `getters.spec.js` vai precisar de ajuste, ver task 08).

## Critério de pronto

- Arrastar para reordenar dentro da coluna surte efeito visível imediato, sem reload.
- Ordem persistida no banco continua correta e consistente com a exibida.
- Caminho escolhido (task 08 ou paliativo) registrado neste arquivo.
- `pnpm test` e `pnpm eslint` limpos.

## Resultado (registrado em 2026-09-21, implementado e verificado na auditoria de 2026-09-18)

**Caminho escolhido: saída 1** - executar a [task 08](08-desmontar-getter-global.md) em vez do
paliativo da saída 2. A 08 foi "feita junto": `getFilteredSortedItemsForStage` e `compareByField`
saíram de `getters.js` (busca no código não acha mais nenhuma das duas fora do histórico do git) e
`KanbanColumn.vue` passou a consumir `getItemsForStage` direto (`KanbanColumn.vue:19,29`). Sem
re-sort no cliente, o board mostra a ordem que o servidor devolveu, e o arrasto não tem mais o que
desfazer - o bug deixou de existir por construção.

A saída 2 **não** foi aplicada (`REORDER_ITEMS` não passou a reescrever `position` em
`$state.items`), como o arquivo pedia: uma só das duas. Nota de precisão: `REORDER_ITEMS` não foi
alterado *por esta task*; a versão que existe hoje (`stageItems[stageId].ids = orderedIds`) veio da
reestruturação por stage da [task 05](05-store-estado-por-stage.md) - no HEAD ela ainda gravava em
`itemOrder`.

Consequências registradas em outras tasks: a divergência de `only_mine` + `assignee_id` (task 17)
foi resolvida no servidor; a ordem exibida passou a ser a de inserção nas mutations, tratada na
[task 28](28-fix-ordem-insercao-destoa-ordem-manual.md).

Pendência de documentação **de código** (fora do escopo desta task, que não altera código): o
comentário de cabeçalho de `pipeline_item_finder.rb` ainda diz que espelha
`getFilteredSortedItemsForStage` "até o frontend trocar para este endpoint" e o comentário do ramo
`assignee` cita `getters.js:13-15` - ambos apontam para código que não existe mais.
