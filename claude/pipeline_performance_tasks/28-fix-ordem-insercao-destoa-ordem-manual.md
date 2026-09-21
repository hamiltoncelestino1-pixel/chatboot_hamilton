# Task 28 — Fix: card inserido no cliente aparece num lugar e no refetch aparece em outro

Severidade: 🟢 Baixa. Achado na revisão de 2026-09-18 (auditoria da implementação das tasks 14-23).

## Objetivo

Com a remoção da ordenação client-side (task 08), a posição em que uma mutation insere um id em
`stageItems[stageId].ids` passou a ser **a** ordem exibida — não há mais um `.sort()` depois para
corrigir. Dois pontos inserem num lugar que não é onde o servidor vai colocar o card no próximo
carregamento:

**1. Card criado entra no fim da lista.** `mutations.js`:

```js
SET_ITEM($state, item) {
  // ...
  $state.stageItems[stageId] = {
    ...existing,
    ids: [...existing.ids, item.id],   // <= sempre no fim
```

Mas o card nasce com `position = 0` (default do schema, nada atribui na criação — ver
[task 24](24-fix-reorder-posicoes-cards-nao-carregados.md)), e a ordem padrão é `position asc`.
No próximo refetch ele aparece **no topo**. O agente cria um card, vê ele embaixo, recarrega, e
ele está em cima.

**2. Card movido por realtime entra no topo.** `actions.js`, em `applyRealtimePipelineItem`:

```js
if (oldStageId !== item.pipeline_stage_id) {
  commit('MOVE_ITEM', {
    itemId: item.id,
    fromStageId: oldStageId,
    toStageId: item.pipeline_stage_id,
    position: 0,   // <= sempre no topo
  });
}
```

`position: 0` aqui é o índice na lista local, não a `position` real do card — o payload do evento
traz `position` (`PipelineItem#push_event_data`), mas ele é ignorado. Antes da task 08 o
`.sort()` do cliente reposicionava o card logo em seguida; agora ele fica no topo da coluna de
destino até alguém refetchar.

Nenhum dos dois corrompe dado — só faz o card "pular de lugar" entre o que o agente vê agora e o
que ele vê depois. Mas num board de CRM, um card que muda de posição sozinho é o tipo de coisa
que gera desconfiança na ferramenta.

## O que corrigir

1. **`applyRealtimePipelineItem`**: usar o `position` que vem no payload para escolher o índice de
   inserção em vez de fixar `0`. Como a lista local é um prefixo ordenado, o índice certo é a
   quantidade de ids carregados cuja `position` é menor (desempatando por `id`, igual ao servidor
   — `PipelineItemFinder#apply_sort`, task 14). Cuidado: isso só vale quando a ordenação ativa é
   `position`; com sort por `value`/`created_at`/etc. o critério é outro. A saída mais simples e
   honesta é inserir pelo critério da ordenação ativa, ou — se isso ficar caro — **não** inserir e
   tratar como card não carregado (cair no ramo de `SET_UNLOADED_ITEM_COUNTED`), deixando o card
   aparecer no lugar certo no próximo fetch. Decidir e registrar.
2. **`SET_ITEM`**: mesma questão para o card recém-criado. Alternativa mais robusta: resolver a
   causa-raiz pela [task 24](24-fix-reorder-posicoes-cards-nao-carregados.md) — se o card nascer
   com `position` no fim da stage, inserir no fim da lista passa a estar **correto** e esta parte
   da task some. Fazer a 24 antes e reavaliar.
3. Conferir o mesmo raciocínio para o rollback de `moveItem` (`position: 0` no commit de
   desfazer) — ali é aceitável porque é um estado transitório de erro, mas vale confirmar que o
   card volta visualmente para onde estava, não para o topo.

## Testes

1. Ordem manual ativa, coluna com mais de uma página: criar um card pelo modal, anotar onde ele
   aparece, recarregar o board e confirmar que está **no mesmo lugar**.
2. Duas sessões: mover um card em B para uma stage que em A está carregada; conferir em A onde ele
   entrou, refetchar (trocar filtro e voltar) e confirmar que não mudou de lugar.
3. Repetir o item 2 com cada ordenação do menu (`value`, `created_at`, `updated_at`, `assignee`) —
   é onde a heurística de índice tem mais chance de errar.
4. Forçar erro no `moveItem` (bloquear o PATCH no DevTools) e confirmar que o card volta para a
   posição de origem, não para o topo.
5. Executar depois da task 24 e reavaliar se o item 2 do "O que corrigir" ainda é necessário.

## Critério de pronto

- Card criado e card movido por realtime aparecem no mesmo lugar antes e depois de um refetch, com
  a ordenação padrão.
- Comportamento decidido e registrado para as ordenações não-`position`.
- Rollback de `moveItem` devolve o card para a posição original.
- `pnpm eslint` limpo.

## Resultado (2026-09-19)

**Item 2 (`SET_ITEM`, card criado): nada a mudar, depois da task 24.** O card agora nasce com
`position` no fim da stage (`PipelineStage#next_position`), então anexar no fim da lista local é o
mesmo lugar que o servidor devolve. Confirmado: `createItem` real numa coluna com 8 cards ficou no
índice 8 no cliente e no índice 8 na resposta do servidor (position 101), sem dupla contagem com o
push do WS. **Decisão registrada** (aceita, não corrigida): numa coluna com mais páginas, o card
criado fica no fim do que está carregado e só vai para o fim real da coluna no próximo refetch, e sob
ordenações que não são `position` o "fim" também não é o lugar do servidor. Manter o card visível
para quem acabou de criá-lo pesa mais que a posição exata nesses casos.

**Item 1 (`applyRealtimePipelineItem`, card movido por realtime):** o índice fixo `0` saiu.
- `realtimeInsertIndex` (actions.js): com ordem manual, índice = primeiro card carregado que vem
  depois de `(position, id)` do card que chegou (mesmo critério do `PipelineItemFinder`). Se o card
  vem depois de tudo que está carregado **e** a coluna tem mais páginas, ou se a ordenação ativa não
  é `position`, retorna `null`.
- **Decisão para `null`:** o card não entra na lista - sai da lista de origem e conta como não
  carregado no destino (`SET_UNLOADED_ITEM_COUNTED`), aparecendo no lugar certo no próximo fetch.
  Reimplementar o comparador do servidor para value/created_at/updated_at/assignee foi descartado.
- Nova mutation `INSERT_STAGE_ITEM`, para o card que só estava contado (sem estar em nenhuma
  lista) e agora tem lugar num destino carregado. O ramo do card só-contado na origem passou a
  entregar a contagem ao destino em vez de ser ignorado.
- Limite: as positions vêm de `state.items`, que não são atualizadas para cards que outra pessoa
  reordenou, então após reordenações manuais o índice pode errar por poucos lugares até o refetch.

**Item 3 (rollback do `moveItem`):** o índice original é lido antes do commit otimista e o rollback
volta para ele, em vez de `0`.

Validado no app real (board aberto + `rails runner` movendo cards, push real; A com 30 cards e mais
de uma página, B com 10):
- Card com `position` 3 movido de B para A: índice 4 no cliente e 4 no servidor (antes: topo, 0);
  contagens A=31, B=9 certas.
- Card com `position` 100 (além do carregado, A com mais páginas): fora da lista, A conta +1 como
  não carregado, B -1.
- Ramo só-contado: A→B→A→B com o mesmo card; no fim entrou em B no índice 8 e a lista de B ficou
  idêntica à do servidor; contagens batendo em cada passo.
- Ordenação por valor ativa: card movido não entra na lista, só conta (A=32, B=8).
- Falha forçada no PATCH (rota inexistente) em `moveItem` de um card no índice 3 de B: lista de B
  idêntica à anterior, card de volta no índice 3, contagens revertidas. XHR restaurado.
Dados de teste removidos (41 cards no pipeline 2309, que estava vazio).

`pnpm eslint`: 0 erros. `pnpm vitest` (kanban): 23/23 (só o `makeState` do spec ganhou
`stageItems: {}`).

**Fora do escopo, não tocado:** um card desconhecido (nunca visto pelo cliente) que chega movido por
realtime continua só contado, nunca inserido, mesmo numa coluna totalmente carregada - é o desenho
original da task 05.
