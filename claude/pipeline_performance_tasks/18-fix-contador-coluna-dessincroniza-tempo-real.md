# Task 18 — Fix: contador da coluna dessincroniza no tempo real (infla e conta em dobro)

Severidade: 🟠 Alta. Achado na revisão de 2026-09-16 (auditoria da implementação das tasks 01-07).

## Objetivo

Com a paginação, o badge da coluna passou a vir de `meta.count` do servidor
(`KanbanColumn.vue:108`) e a ser mantido no cliente por deltas. Duas formas de esse delta
divergir da realidade, ambas no mesmo par de arquivos.

### Caso 1 — update de card não carregado infla o contador

`app/javascript/dashboard/store/modules/kanban/actions.js:320-335`:

```js
applyRealtimePipelineItem: ({ commit, state, rootGetters }, item) => {
  if (state.activePipelineId !== item.pipeline_id) return;
  const currentUserId = rootGetters.getCurrentUserID;
  const stillMatches = itemMatchesActiveFilters(state, item, currentUserId);
  const existingItem = state.items[item.id];

  if (!existingItem) {
    if (stillMatches) {
      commit('ADJUST_STAGE_ITEMS_COUNT', { stageId: item.pipeline_stage_id, delta: 1 });
    }
    return;
  }
  // ...
```

O ramo `!existingItem` assume "card novo". Mas os dois eventos caem no **mesmo** handler
(`app/javascript/dashboard/helper/actionCable.js:38-39`):

```js
'pipeline_item.created': this.onPipelineItemChanged,
'pipeline_item.updated': this.onPipelineItemChanged,
```

Então um card que está na página 3 (não existe em `state.items`) faz `+1` no contador **a cada
`pipeline_item.updated` que receber**. Uma automação ou macro que mexe em 50 cards não
carregados infla o badge em 50. O comentário do código documenta o gap do *decremento* da stage
de origem, mas não este.

### Caso 2 — corrida entre o POST e o broadcast conta em dobro

`app/javascript/dashboard/store/modules/kanban/mutations.js:155-165`:

```js
SET_ITEM($state, item) {
  $state.items[item.id] = item;
  const stageId = item.pipeline_stage_id;
  const existing = $state.stageItems[stageId] || emptyStageItemsState();
  if (existing.ids.includes(item.id)) return;
  $state.stageItems[stageId] = { ...existing, ids: [...existing.ids, item.id], count: existing.count + 1 };
},
```

Quando o próprio agente cria um card, o caminho feliz é: `createItem` → `SET_ITEM` (+1), e
depois o broadcast chega, `existingItem` já existe, nada acontece. Mas o broadcast pode chegar
**antes** da resposta REST (`ActionCableListener` é síncrono no request e enfileira
`ActionCableBroadcastJob` na fila `:critical`). Nessa ordem:

1. WS chega → `!existingItem` → `ADJUST_STAGE_ITEMS_COUNT +1` (o id **não** entra em `ids`);
2. resposta REST chega → `SET_ITEM` → `existing.ids.includes(id)` é `false` → adiciona e **+1 de
   novo**.

Contador fica 2 acima do real.

Nos dois casos o valor se corrige sozinho no próximo fetch de página 1 (`SET_STAGE_ITEMS_PAGE`
grava `count` do `meta`), ou seja: troca de pipeline, mudança de filtro/ordenação ou reload. Mas
durante uma sessão de trabalho normal o badge vai derivando pra cima, e `hasMore`
(`ids.length < count`) fica `true` indevidamente, provocando fetch de página vazia.

## O que corrigir

A raiz é a mesma nos dois: o contador é ajustado por delta cego, sem saber se aquele card já foi
contado. Fix estrutural em vez de dois remendos:

1. Tornar o ajuste **idempotente por item**. As opções, em ordem de preferência:
   - manter um conjunto de ids já contabilizados por stage (além de `ids`, que só tem os
     carregados) e só aplicar o delta quando o id entra/sai desse conjunto;
   - ou distinguir create de update de verdade. Os dois eventos existem separados no backend
     (`lib/events/types.rb`) e são achatados em `actionCable.js:38-39` — separar os handlers é
     possível, mas resolve só o caso 1, não a corrida do caso 2. Por isso a primeira opção é a
     preferida.
2. Fazer `SET_ITEM` e `ADJUST_STAGE_ITEMS_COUNT` passarem pelo mesmo caminho de bookkeeping, para
   que o `+1` do POST e o `+1` do WS não possam se somar.
3. Revisar, no mesmo esforço, o gap já documentado no comentário de `actions.js:314-319`: quando
   um card **não carregado** sai de uma stage, o contador da origem não é decrementado. Com um
   conjunto de ids contabilizados isso fica resolvido de graça se o payload do evento trouxer a
   stage anterior — conferir se `push_event_data` (`app/models/pipeline_item.rb:95-115`) tem essa
   informação; se não tiver, decidir explicitamente se vale acrescentar ou se continua sendo um
   gap aceito (nesse caso, atualizar o comentário para refletir a decisão).

## Testes

Duas sessões abertas no mesmo board (A e B), coluna com mais cards que uma página:

1. **Caso 1:** em B, editar repetidamente (5x) um card que em A está numa página ainda não
   carregada. Em A, o badge não pode subir. Comparar com o valor real no banco.
2. **Caso 2:** em A, criar um card e conferir que o badge subiu exatamente 1. Repetir com a rede
   estrangulada no DevTools (para forçar o WS a chegar antes do POST) e conferir o mesmo.
3. Mover um card carregado entre colunas (nas duas sessões) e conferir que os dois badges se
   ajustam corretamente, nos dois sentidos.
4. Apagar um card e exportar um card para outro pipeline — badge decrementa uma vez só.
5. Card que deixa de casar com o filtro ativo (mudar responsável com filtro por responsável
   ligado): sai da lista e decrementa uma vez.
6. Depois de cada cenário, trocar de pipeline e voltar: o badge tem que ser igual ao que já
   estava (prova que o estado do cliente não tinha derivado).
7. `pnpm test` — specs de `store/modules/kanban/specs/` passando; vale acrescentar caso para a
   idempotência se os specs já cobrirem mutations (checar antes; regra do `AGENTS.md` é não
   escrever spec sem pedir, mas os arquivos já existem e já foram tocados nesta leva).

## Critério de pronto

- Badge da coluna não deriva depois de uma sessão de trabalho com automação/macro rodando.
- Criar card conta exatamente 1, independente da ordem em que POST e WS chegam.
- Decisão sobre o decremento da stage de origem registrada (implementado ou aceito, com o
  comentário do código atualizado para bater com a realidade).
- `pnpm test` e `pnpm eslint` limpos.

## Resultado (2026-09-17)

Fix estrutural, opção preferida do documento: `stageItems[stageId]` ganhou `unloadedCountedIds`
(ids que contam pro `count` sem estar carregados em `ids`). `ADJUST_STAGE_ITEMS_COUNT` (delta
cego) foi **removida** e substituída por `SET_UNLOADED_ITEM_COUNTED($state, { stageId, itemId,
counted })`, idempotente por id — chamar de novo com o mesmo `counted` não faz nada. `SET_ITEM`
(o `createItem` da API) agora consulta esse mesmo conjunto antes de somar +1, então o POST e o
WS não conseguem mais se somar. `SET_STAGE_ITEMS_PAGE` reseta o conjunto inteiro (page 1 traz
`count` autoritativo do servidor, invalida qualquer bookkeeping anterior); `APPEND_STAGE_ITEMS_PAGE`
só remove os ids que viraram carregados, sem mexer no `count` (paginação não é um refresh de
contagem).

**Item 3 (decremento da stage de origem para item não carregado): gap aceito**, não implementado.
`PipelineItem#push_event_data` não carrega `previous_stage_id` — só a stage atual. Adicionar
isso ao payload do evento é uma mudança de contrato do backend ortogonal ao fix estrutural desta
task (que já resolve os dois bugs realmente medidos); PIPELINE_ITEM_STAGE_CHANGED carrega essa
info mas não é consumido pelo ActionCableListener (task 12). Comentário do código atualizado
para descrever isso como gap conhecido e aceito, não um TODO esquecido.

Validado no Docker local via `store.dispatch`/`store.commit` diretos na aplicação real (não só
specs mockadas):
- 5 pushes seguidos de `pipeline_item.updated` pro mesmo card não-carregado (simulando macro em
  lote): contador foi 0→1 na primeira e **ficou em 1** nas 4 seguintes (antes do fix teria virado
  5).
- Corrida WS-antes-do-POST: WS conta 1, depois `SET_ITEM` (POST) chega pro mesmo id — contador
  **ficou em 1** (antes do fix teria virado 2), e o id migrou corretamente de
  `unloadedCountedIds` pra `ids`.
- Corrida POST-antes-do-WS: `SET_ITEM` conta 1 (item novo de verdade), WS chega depois pro mesmo
  id já carregado — contador **ficou o mesmo**, sem dobrar.

`pnpm vitest` (kanban): 23/23 passando (2 specs de `applyRealtimePipelineItem` atualizadas pra
refletir o novo commit `SET_UNLOADED_ITEM_COUNTED`). `pnpm eslint`: 0 erros.
