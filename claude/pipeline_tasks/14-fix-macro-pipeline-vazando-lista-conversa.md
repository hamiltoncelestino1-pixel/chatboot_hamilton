# Task 14 — Fix: macros de pipeline vazam para a lista de macros da conversa

Task de correção pós-implementação da task 08. Achado na auditoria de 2026-08-01. Prioridade
alta — é um bug de produto visível ao usuário final, com falso positivo enganoso (toast de
sucesso quando a ação na verdade não roda).

## Objetivo

A task 08 introduziu `macro_type` justamente para permitir "ao frontend filtrar quais macros
aparecem no Kanban vs. na conversa" (task 06, item 1). O filtro foi aplicado corretamente em um
lugar, mas não no outro:

- `app/javascript/dashboard/routes/dashboard/kanban/components/KanbanRunMacroMenu.vue` — filtra
  corretamente: `macros.value.filter(macro => macro.macro_type === 'pipeline_item')`.
- `app/javascript/dashboard/routes/dashboard/conversation/Macros/List.vue` — **não foi tocado**
  pelo épico e continua usando `macros.value` (getter `macros/getMacros`) cru, sem nenhum filtro
  por `macro_type`. Como o backend (`Macro.with_visibility`) e o Vuex `macros/get` retornam
  **todos** os macros da conta (ambos os tipos) numa lista compartilhada, uma macro
  `macro_type: pipeline_item` passa a aparecer também no painel de macros de uma conversa
  qualquer.

**Cenário de falha concreto:**
1. Usuário cria uma macro `macro_type: pipeline_item` com ação `move_pipeline_item_stage`.
2. Essa macro aparece na lista de macros de uma conversa (`List.vue` → `MacroItem.vue`).
3. Clicar no preview (`MacroPreview.vue`) chama `resolveActionName(action.action_name)`
   (`app/javascript/dashboard/routes/dashboard/settings/macros/macroHelper.js`), que só busca em
   `MACRO_ACTION_TYPES` (as ações de conversa) — `.find(...)` retorna `undefined`, e o acesso a
   `.label` nesse `undefined` lança `TypeError`, quebrando a renderização do preview.
4. Clicar em "executar" despacha `macros/execute` com `conversationIds`, caindo no branch
   `MacrosExecutionJob`/`Macros::ExecutionService` — que não inclui `PipelineItemActions` e não
   conhece `move_pipeline_item_stage` (`NoMethodError`, engolido pelo rescue por-ação genérico). A
   macro "executa" sem fazer nada, mas o frontend mostra o toast de sucesso
   (`MACROS.EXECUTE.EXECUTED_SUCCESSFULLY`) — falso positivo enganoso para o usuário.

## O que corrigir

Em `app/javascript/dashboard/routes/dashboard/conversation/Macros/List.vue`, filtrar
`macros.value` por `macro_type === 'conversation'` antes de renderizar — mirror direto (inverso)
do filtro já correto em `KanbanRunMacroMenu.vue`:

```js
const macros = useMapGetter('macros/getMacros');
const conversationMacros = computed(() =>
  (macros.value ?? []).filter(macro => macro.macro_type === 'conversation')
);
```

E usar `conversationMacros` em vez de `macros` no restante do componente (`orderedMacros`,
contagem, estado vazio, `Draggable`).

Confirmar também se `MacroItem.vue`/`MacroPreview.vue` (usados tanto pela conversa quanto,
indiretamente, por outras telas) precisam de alguma guarda adicional, ou se o filtro em `List.vue`
já é suficiente por ser o único ponto de entrada real dessa lista na conversa.

## Testes

- Se houver spec de componente para `List.vue` (verificar se existe hoje) — adicionar caso: lista
  contém macros dos dois tipos, só as `macro_type: conversation` aparecem renderizadas.
- QA manual: criar uma macro de pipeline e uma de conversa na mesma conta; abrir uma conversa
  qualquer e confirmar que só a macro de conversa aparece na lista; abrir um card no Kanban e
  confirmar que só a macro de pipeline aparece no menu "Rodar macro".

## Critério de pronto

- Macros `macro_type: pipeline_item` não aparecem mais na lista de macros de conversa.
- Preview e execução de macros de conversa continuam funcionando normalmente (sem regressão).
- QA manual confirmando a separação nos dois pontos (conversa e Kanban).
