# Task 25 — Fix: a poda de memória do `SET_ACTIVE_PIPELINE` não descarta nada

Severidade: 🟠 Alta. Achado na revisão de 2026-09-18 (auditoria da implementação das tasks 14-23).

## Objetivo

A [task 10](10-memoria-do-store-kanban.md) entregou duas coisas: os índices de lookup
(`itemIdsByContact`/`itemIdsByConversation`, que funcionam e eliminaram o `Object.values(...).filter(...)`
dos getters — isso está certo) e a poda de `$state.items` ao trocar de pipeline. **A segunda é um
no-op.**

`app/javascript/dashboard/store/modules/kanban/mutations.js`:

```js
SET_ACTIVE_PIPELINE($state, pipelineId) {
  $state.activePipelineId = pipelineId;
  $state.stageItems = {};

  const keepIds = new Set(
    [
      ...Object.values($state.itemIdsByContact),
      ...Object.values($state.itemIdsByConversation),
    ].flat()
  );
  $state.items = Object.fromEntries(
    Object.entries($state.items).filter(([id]) => keepIds.has(Number(id)))
  );
},
```

O comentário acima dela diz: *"Anything not referenced by the contact/conversation lookup indices
is safe to drop here - it only ever came from a column of the pipeline just left."*

Só que **todo card que o board carrega entra no índice de contato**:

```js
SET_STAGE_ITEMS_PAGE($state, { stageId, items, count, page }) {
  items.forEach(item => {
    syncItemIndices($state, $state.items[item.id], item);   // <= aqui
    $state.items[item.id] = item;
  });
```

e `syncItemIndices` só ignora a chave quando ela não está no patch:

```js
if ('contact' in patch) { ... }
```

`app/views/api/v1/models/_pipeline_item.json.jbuilder:14-20` emite `contact` **incondicionalmente**
(`contact_id` é `NOT NULL` no schema), então `'contact' in patch` é sempre verdadeiro para um item
vindo da API. Resultado: `keepIds` contém todo card já carregado por qualquer coluna, e o
`filter` não remove nada.

Efeito prático: o vazamento que a task 10 dizia ter resolvido continua igual — `$state.items`
cresce pela sessão inteira do agente — e agora `itemIdsByContact` cresce junto, uma entrada por
contato com a lista de ids. Pior que o diagnóstico original, não melhor.

## O que corrigir

O índice precisa saber **por que** um id está nele. Hoje ele mistura duas origens com ciclos de
vida diferentes:

- **board** (`SET_STAGE_ITEMS_PAGE`, `APPEND_STAGE_ITEMS_PAGE`, `SET_ITEM`): descartável ao trocar
  de pipeline, junto com `stageItems`;
- **painel de Oportunidades** (`SET_ITEM_DATA`, via `fetchItemsForContact`/`fetchItemsForConversation`):
  tem que sobreviver à troca de pipeline, porque o painel pode estar aberto — é exatamente o
  cenário de regressão que a task 10 listou nos testes.

Opções, em ordem de preferência:

1. **Indexar só o que vem de `SET_ITEM_DATA`.** Os getters `getItemsForContact`/`getItemsForConversation`
   são consumidos apenas por `ContactOpportunities.vue` e `ConversationOpportunities.vue`, que
   sempre despacham o próprio fetch antes de ler (conferir isso antes de fechar a decisão — se
   algum deles depender de um card que só o board trouxe, esta opção quebra o painel).
   Aí a poda volta a significar o que o comentário diz.
2. **Marcar a origem no índice** (ex. dois conjuntos, ou um flag por id) e podar o que só o board
   referenciava. Mais robusto, mais estado para manter em sincronia em 6 mutations.

Em qualquer uma: podar **também os índices**, não só `$state.items`. Hoje um id removido de
`items` continuaria listado em `itemIdsByContact` se a poda funcionasse — os getters filtram por
`Boolean` e não quebram, mas o índice vira lixo acumulado.

Corrigir o comentário da mutation junto com o código — ele afirma um comportamento que não
acontece, o que é pior do que não ter comentário.

## Testes

1. Vue DevTools com o board aberto num pipeline grande: anotar `Object.keys(store.state.kanban.items).length`,
   trocar de pipeline, e conferir que o número **caiu**. Hoje ele não cai — medir antes de mexer,
   para ter a baseline.
2. Mesma medição para `itemIdsByContact`/`itemIdsByConversation`.
3. **Regressão do painel de Oportunidades** (o cenário que a task 10 já previa): abrir uma conversa
   com card vinculado, confirmar que o painel lista a oportunidade, trocar de pipeline no board com
   a conversa aberta, e confirmar que o painel **não** esvazia.
4. Mesmo teste pelo contato (`ContactOpportunities.vue`) e por `ContactManageView.vue`.
5. Navegar por ~20 conversas seguidas e confirmar que nem `items` nem os índices crescem sem
   limite.
6. Cenário do badge de tarefa vencida (`claude/crm_features_fixes_tasks/04-*.md`): abrir a conversa
   vinculada a um card com tarefa vencida e voltar ao board sem reload — o badge continua visível.
7. `pnpm test` — o módulo kanban hoje **não tem spec nenhuma de mutations** (só getters e algumas
   actions), então esta é uma das poucas áreas onde vale propor cobertura ao usuário antes de
   fechar (regra do `AGENTS.md`: não escrever spec sem pedir).

## Critério de pronto

- Trocar de pipeline reduz de fato o tamanho de `$state.items`, comprovado por medição.
- Índices podados junto, sem ids órfãos.
- Painéis de Oportunidades (conversa e contato) inalterados, inclusive com o board em outro
  pipeline.
- Comentário da mutation descreve o comportamento real.
- `pnpm eslint` limpo.

## Resultado (2026-09-19)

O achado estava certo e a falha era minha (task 10): a validação que fiz na época só confirmou
que o painel não esvaziava depois da troca — nunca medi se `items` **diminuía**.

**Baseline medida antes de mexer** (12 cards semeados no pipeline 2308, board carregado, troca
para o 153): `items` 12 → **12**, `itemIdsByContact` 12 → **12**. No-op confirmado.

**Saída 1 (indexar só o que vem de `SET_ITEM_DATA`)**, com um refinamento: `syncItemIndices`
ganhou a opção `addNew`, e só `SET_ITEM_DATA` (o fetch dos painéis) passa `addNew: true`. Todas
as outras escritas (páginas do board, `SET_ITEM`, `EDIT_ITEM`) só mantêm consistente um id que
**já está** no índice — movem de bucket ou tiram, nunca adicionam. Com isso a poda em
`SET_ACTIVE_PIPELINE` passa a significar o que o comentário diz, e o comentário foi reescrito
para descrever o comportamento real. Índices: não precisaram de poda própria — só listam ids
que a poda preserva, e `DELETE_ITEM` já os remove.

**Premissa da saída 1 conferida, e estava furada**: os únicos leitores dos getters são
`ContactOpportunities.vue` e `ConversationOpportunities.vue` (`ContactManageView.vue` só
despacha um fetch próprio). Mas `ContactPanel` **não é remontado ao trocar de conversa**
(`ConversationSidebar.vue` não usa `:key`, só a prop `conversationId` muda) e os dois painéis só
buscavam em `onMounted` — antes o índice cheio de cards do board disfarçava isso. Troquei o
`onMounted` por `watch(() => id, fetch, { immediate: true })` nos dois.

**Depois, medido na aplicação real**:
- Board carregado: `items` 12, `itemIdsByContact` **0** (cards do board não entram mais).
- Painel busca um contato → índice com 1 entrada; troca de pipeline → `items` 12 → **1** (só o
  card do painel sobrevive), índice intacto, painel continua vendo o card.
- Fluxo de UI: página do contato → aba Oportunidades lista o card → clicar nele navega para
  `?pipelineId=2308&itemId=…` e o detalhe do card abre.
- Índice de conversa: fetch → `{1990: [id]}`; troca de pipeline mantém; desvincular via
  `EDIT_ITEM` (`conversation_id: null`) remove o id e a chave (sem órfão); revincular via
  `EDIT_ITEM` **não** adiciona de volta (só o fetch do painel adiciona — por desenho).

`pnpm eslint`: 0 erros. `pnpm vitest` (kanban): 23/23. Sem spec de mutations no módulo — não
escrevi (regra do `AGENTS.md`); fica como sugestão de cobertura se você quiser.

**Resíduo conhecido, não resolvido**: entradas de lookup (uma por contato/conversa visitados)
ficam no store pela sessão inteira — a troca de pipeline as **preserva** de propósito (o painel
pode estar aberto, e o clique em "oportunidade → board" depende do card já estar em `items`).
É um vazamento bem menor que o original (só o que os painéis buscaram, não colunas inteiras),
mas o teste 5 ("~20 conversas seguidas sem crescer") **não** passaria estritamente. Soltar a
entrada quando o painel desmonta quebraria o clique que abre o detalhe de um card fora da
primeira página; o caminho certo seria o board buscar o card por id quando ele não estiver no
store. Fica como decisão sua se vale.
