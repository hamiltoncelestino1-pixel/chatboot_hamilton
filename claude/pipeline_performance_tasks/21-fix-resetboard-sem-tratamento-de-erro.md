# Task 21 — Fix: falha ao carregar uma coluna quebra o board em silêncio

Severidade: 🟡 Média. Achado na revisão de 2026-09-16 (auditoria da implementação das tasks 01-07).

## Objetivo

Nenhuma das ações de fetch por coluna trata erro — só `try/finally`.

`app/javascript/dashboard/store/modules/kanban/actions.js:21-38` e `:42-63`:

```js
fetchStageItems: async ({ commit, state }, { pipelineId, stageId }) => {
  commit('SET_STAGE_FETCHING', { stageId, isFetching: true });
  try {
    const { data } = await PipelinesAPI.getBoardItems(pipelineId, { ... });
    commit('SET_STAGE_ITEMS_PAGE', { ... });
  } finally {
    commit('SET_STAGE_FETCHING', { stageId, isFetching: false });
  }
},
```

E `resetBoard` (`:67-75`) junta todas num `Promise.all`:

```js
await Promise.all(
  stageIds.map(stageId => dispatch('fetchStageItems', { pipelineId, stageId }))
);
```

Consequências de **uma única coluna** falhar (rede instável, 500, timeout):

1. O `Promise.all` rejeita, e o `await store.dispatch('kanban/resetBoard')` dentro do watcher de
   `KanbanIndex.vue:44` gera uma unhandled rejection — o erro só aparece no console.
2. A coluna que falhou fica no estado default de `emptyStageItemsState()`:
   `{ ids: [], page: 1, count: 0, hasMore: true }`. Na tela isso é **indistinguível de uma coluna
   legitimamente vazia**: badge `0`, nenhum card, nenhuma mensagem.
3. Pior: `hasMore` é `true` com `ids` vazio, então o `IntersectionObserver`
   (`KanbanColumn.vue:171-176`) renderiza, enxerga a área vazia e dispara `fetchMoreStageItems`,
   que pede a **página 2** de uma coluna cuja página 1 nunca carregou. Se essa também falhar, a
   coluna fica presa: `page` nunca avança, e a sentinela só volta a disparar quando a
   interseção mudar.
4. O agente não tem como saber que está vendo um board incompleto — e num board de CRM isso é
   pior que um erro visível: ele pode concluir que uma oportunidade sumiu.

O flag global `isFetchingItems` foi removido do `uiFlags` (`index.js:20-26`) junto com o
`fetchItems` antigo, então também não existe mais um indicador de erro no nível do board.

## O que corrigir

1. `catch` em `fetchStageItems` e `fetchMoreStageItems`, marcando um estado de erro por coluna
   no `stageItems` (ex. `hasError: true`) além de encerrar o `isFetching`.
2. Enquanto `hasError`, **não** renderizar o `IntersectionObserver` — senão o observador continua
   tentando puxar páginas de uma coluna quebrada (item 3 acima). Mostrar em vez disso um estado
   de erro com ação de "tentar de novo" no `KanbanColumn.vue`, que redisparar `fetchStageItems`.
3. `resetBoard` não pode rejeitar por causa de uma coluna: usar `Promise.allSettled`, ou deixar o
   `catch` de cada ação absorver. Uma coluna quebrada não deve impedir as outras de carregar.
4. Chaves de i18n novas para o estado de erro e o botão de retry, em `en/kanban.json` **e**
   `pt_BR/kanban.json` (exceção do domínio Kanban documentada no `AGENTS.md`).
5. Decidir se vale também um `useAlert` no nível do board quando alguma coluna falha — o módulo
   já usa esse padrão em `actions.js:236,245,259`. Um alerta por coluna seria ruído; um só,
   agregado, faz sentido.

## Testes

1. Bloquear o endpoint no DevTools (Network → block request URL) para **uma** stage e recarregar
   o board: as outras colunas carregam normalmente, a que falhou mostra estado de erro explícito
   (não "0 cards"), e não há unhandled rejection no console.
2. Clicar em "tentar de novo" com o bloqueio removido: a coluna carrega.
3. Bloquear e conferir na aba Network que a coluna quebrada **não** fica disparando requests de
   página 2 em loop.
4. Derrubar o container do Rails (`docker stop chatwoot-noble-rails-1`) com o board aberto e
   trocar um filtro: comportamento degradado, mas visível e recuperável.
5. Coluna legitimamente vazia (0 cards de verdade) continua mostrando o estado vazio normal, não
   o de erro — os dois não podem se confundir.

## Critério de pronto

- Falha em uma coluna não derruba as outras nem some em silêncio.
- Coluna com erro é visualmente distinta de coluna vazia, e é recuperável sem reload.
- Sem unhandled rejection no console em nenhum cenário de falha.
- Chaves novas em `en/kanban.json` e `pt_BR/kanban.json`.
- `pnpm eslint` limpo (atenção a `vue/no-bare-strings-in-template`).

## Resultado (2026-09-18)

`stageItems[stageId]` ganhou `hasError` (default `false` em `emptyStageItemsState`, limpo de
volta a `false` em todo fetch bem-sucedido — página 1 ou "load more"). Nova mutation
`SET_STAGE_ERROR`. `fetchStageItems`/`fetchMoreStageItems` ganharam `catch` que commita o erro
em vez de deixar a rejection subir; `resetBoard` continua com `Promise.all` (não precisou virar
`allSettled` — como as duas actions agora absorvem o próprio erro, nenhuma delas rejeita mais) e,
no fim, dispara **um** `useAlert` agregado se 1+ colunas falharam (mesmo padrão de string simples
sem `t()` já usado nas outras chamadas de `useAlert` deste arquivo).

`KanbanColumn.vue`: novo estado de erro (ícone + texto + botão "tentar de novo") tanto para o
caso "nada carregou" (página 1 falhou) quanto no rodapé da coluna (uma página seguinte falhou,
cards já carregados continuam visíveis) — nos dois casos o `IntersectionObserver` **não**
renderiza enquanto `hasError` for `true` (guard no `v-else-if`), então não há como ele reentrar
em loop pedindo página 2 de uma coluna quebrada. `retryLoad()` decide sozinho qual action
redisparar: `fetchStageItems` se nada carregou, `fetchMoreStageItems` (via `loadMoreItems`) se já
havia cards na tela.

Chaves novas `KANBAN.COLUMN.ERROR`/`KANBAN.COLUMN.RETRY` em `en/kanban.json` **e**
`pt_BR/kanban.json`.

Validado no Docker local **de ponta a ponta com a aplicação real**, não só o código lido:
interceptei XHR no navegador pra forçar a request de uma stage específica a falhar
(`stage_id=7816`), disparei `store.dispatch('kanban/resetBoard')` de verdade e:
- A coluna bloqueada terminou com `hasError: true`; as outras três, `hasError: false` — nenhuma
  derrubou as outras.
- Console sem unhandled rejection (só ruído pré-existente de dev tooling, confirmado antes em
  outras tasks desta sessão).
- Screenshot: a coluna quebrada mostrou "⚠ Não foi possível carregar esses cards" + "Tentar de
  novo"; a coluna vazia de verdade ao lado não mostrou nada disso — visualmente distintas.
- Removi a interceptação e cliquei em "Tentar de novo" de verdade: a coluna recuperou
  (`hasError` voltou a `false`) sem reload de página.

`pnpm vitest` (kanban): 23/23 passando. `pnpm eslint`: 0 erros.
