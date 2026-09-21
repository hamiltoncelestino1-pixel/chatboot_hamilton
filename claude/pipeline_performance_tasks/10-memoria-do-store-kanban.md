# Task 10 — `$state.items` cresce indefinidamente e é varrido linearmente

Severidade: 🟡 Média. Achado na análise de performance de 2026-09-15.
Depende da task 05 (a estrutura de estado muda ali).

## Objetivo

### 1. Memória que nunca é liberada

`store/modules/kanban/mutations.js:150-153`:

```js
SET_ACTIVE_PIPELINE($state, pipelineId) {
  $state.activePipelineId = pipelineId;
  $state.itemOrder = {};
},
```

Trocar de pipeline limpa a **ordem**, mas não o dicionário `$state.items`. Os cards do pipeline
anterior ficam na memória para sempre. Somando isso a `fetchItemsForContact`/
`fetchItemsForConversation` (`actions.js:237-247`), que jogam cards de qualquer pipeline no
mesmo dicionário toda vez que o agente abre uma conversa ou um contato, o store cresce durante
toda a sessão do agente — que costuma ficar aberta o dia inteiro.

### 2. Varredura linear por contato/conversa

`store/modules/kanban/getters.js:101-107`:

```js
getItemsForContact: $state => contactId =>
  Object.values($state.items).filter(i => i.contact?.id === contactId),

getItemsForConversation: $state => conversationId =>
  Object.values($state.items).filter(i => i.conversation_id === conversationId),
```

Method-style de novo (sem cache), `Object.values` aloca um array com **todos** os cards
acumulados, e o `.filter()` varre tudo. São os getters de `ContactOpportunities.vue:20` e
`ConversationOpportunities.vue:20` — painéis que o agente abre e fecha o tempo todo navegando
entre conversas. Quanto mais o agente usa o sistema, mais lento fica abrir uma conversa.

## O que corrigir

1. Limpar `$state.items` em `SET_ACTIVE_PIPELINE`, ou podar os cards que não pertencem mais a
   nenhuma coluna carregada. **Cuidado:** os painéis de Oportunidades leem do mesmo dicionário
   e podem estar montados enquanto o board troca de pipeline — limpar sem critério faria o
   painel esvaziar na cara do agente. A poda precisa preservar (ou refazer) os itens que os
   painéis abertos estão usando; o comentário de `mutations.js:117-118` sobre `SET_ITEM_DATA`
   mostra que essa separação entre "dados do board" e "dados de lookup" já foi pensada antes.
2. Manter índices `itemIdsByContact` / `itemIdsByConversation` alimentados nas mutations que
   escrevem em `items` (`SET_ITEMS`, `SET_ITEM`, `SET_ITEM_DATA`, `EDIT_ITEM`, `DELETE_ITEM`),
   e os dois getters passam a mapear ids em vez de varrer. É o mesmo padrão de
   `ids → map → filter(Boolean)` que o módulo já usa em `getItemsForStage` (`getters.js:31-34`).
3. Revisar se `getItemsForContact`/`getItemsForConversation` precisam continuar method-style
   depois do índice — se o painel sempre pede um id só, dá pra manter, o custo vira O(k).

## Testes

1. Abrir o board de um pipeline grande, trocar para outro pipeline, e inspecionar
   `store.state.kanban.items` no Vue DevTools: os cards do pipeline anterior não devem estar
   mais lá (ou só os que algum painel aberto usa).
2. **Regressão do painel de Oportunidades:** abrir uma conversa com card vinculado, confirmar
   que o painel mostra a oportunidade; trocar de pipeline no board com a conversa aberta e
   confirmar que o painel **não** esvazia.
3. Navegar por ~20 conversas diferentes seguidas e confirmar, no DevTools, que o dicionário não
   cresce sem limite e que o tempo de abrir o painel não degrada.
4. Cenário do bug da `claude/crm_features_fixes_tasks/04-*.md`: abrir a conversa/contato
   vinculado a um card com tarefa vencida e voltar ao board sem reload — o badge de atrasado
   tem que continuar visível (a poda não pode reintroduzir aquele problema).

## Critério de pronto

- `$state.items` não acumula cards de pipelines fechados nem de contatos já visitados.
- Painéis de Oportunidades (conversa e contato) continuam funcionando, inclusive com o board
  aberto em outro pipeline.
- `getItemsForContact`/`getItemsForConversation` não varrem mais o dicionário inteiro.
- Badge de tarefa vencida não regride (cenário 4).
- `pnpm test` e `pnpm eslint` limpos.
