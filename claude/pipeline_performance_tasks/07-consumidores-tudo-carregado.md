# Task 07 — Consertar os consumidores que assumem "tudo carregado"

Severidade: 🟠 Alta. Achado na análise de performance de 2026-09-15.
Depende da task 05.

## Objetivo

Dois pontos fora do board leem o store do Kanban assumindo que ele tem **todos** os cards.
Depois da paginação eles passam a ler só a página carregada, e o pior é que ambos falham
silenciosamente — mostram um número menor ou fazem menos trabalho, sem erro nenhum.

### 1. Contagem em Configurações → Pipelines

`app/javascript/dashboard/routes/dashboard/settings/pipelines/PipelineStagesSection.vue:44-45`:

```js
const itemsInStage = stage =>
  store.getters['kanban/getItemsForStage'](stage.id)?.length || 0;
```

Depois da paginação isso vira "quantos cards dessa coluna estão carregados no board agora" —
que pode ser 0 se o agente nunca abriu aquele pipeline. A API já devolve o número certo:
`items_count` no `_pipeline_stage.json.jbuilder:8` (corrigido pela task 01) e disponível em
`$state.stages[id]` via `SET_PIPELINES` (`mutations.js:30-35`).

### 2. "Rodar macro na coluna"

`app/javascript/dashboard/routes/dashboard/kanban/components/KanbanColumn.vue:84-88`:

```vue
<KanbanRunMacroMenu
  v-if="localItems.length"
  :pipeline-item-ids="localItems.map(item => item.id)"
  button-class="..."
/>
```

O menu no cabeçalho da coluna é o "rodar macro em todos os cards desta coluna". Com paginação
ele roda só nos cards da página visível — o agente clica achando que aplicou em 900 cards e
aplicou em 25. Esse é o efeito colateral mais perigoso de toda a paginação, porque a ação é
destrutiva-ish (move cards, cria tasks, muda responsável) e não dá pra desfazer.

`KanbanRunMacroMenu.vue:54-77` dispara `macros/execute` com `pipelineItemIds` e o backend
enfileira `MacrosPipelineExecutionJob`.

Nota: o mesmo componente é usado no card individual (`KanbanCard.vue:78-81`,
`:pipeline-item-ids="[item.id]"`) — esse uso não é afetado.

## O que corrigir

1. `PipelineStagesSection.vue:44-45` → ler `stage.items_count` da API em vez de contar o store.
2. Decidir e implementar o escopo do "rodar macro na coluna". Duas saídas, em ordem de
   preferência:
   - **Server-side por stage**: o endpoint de execução de macro passa a aceitar `stage_id`
     (+ os filtros ativos) em vez de uma lista de ids, e o job resolve os cards no servidor.
     É a solução correta e a única que continua fazendo o que o agente espera. Envolve backend
     (`macros_controller`, `Macros::PipelineExecutionService`) e Swagger — pode virar uma task
     própria se crescer.
   - **Escopo explícito na UI**: manter a lista de ids e deixar claro no rótulo/confirmação que
     a macro roda nos N cards carregados. Mais barato, mas piora a feature.

   Se a opção server-side for escolhida, atenção ao comentário de `KanbanRunMacroMenu.vue:64-72`
   sobre não refetchar depois do dispatch (o board se atualiza pelos broadcasts do job) — essa
   decisão continua válida e não deve ser desfeita.

## Testes

1. `Configurações → Pipelines`: a contagem de cada stage bate com o board, **sem** ter aberto o
   board antes (recarregar a página direto nessa tela).
2. Coluna com mais cards que uma página: rodar uma macro pelo cabeçalho e confirmar, no banco
   ou recarregando, que ela atingiu o escopo prometido (todos ou os N carregados, conforme a
   decisão) — contar antes e depois, não confiar na mensagem de sucesso.
3. Rodar macro pelo card individual continua afetando só aquele card.

## Critério de pronto

- Contagem em Configurações vem da API, não do store do board.
- Escopo do "rodar macro na coluna" decidido, implementado e **visível pro agente** — não pode
  ficar ambíguo.
- Nenhum dos dois pontos depende mais de "o board carregou tudo".
- `pnpm eslint` limpo; se mexer no backend, `bundle exec rubocop -a` e Swagger em dia.
