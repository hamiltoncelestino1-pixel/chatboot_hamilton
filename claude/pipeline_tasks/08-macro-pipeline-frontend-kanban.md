# Task 08 — Macros: UI "Rodar macro" no Kanban + editor

Parte do Grupo C ([visão geral](00-visao-geral.md)). Depende das tasks 06 e 07 (backend
completo).

## Objetivo

Permitir criar macros de pipeline no editor de macros existente, e rodá-las a partir do
Kanban — mirror da experiência já existente de macros de conversa
(`conversation/Macros/List.vue` + `MacroItem.vue`, acessível a partir de `ContactPanel.vue`).

## 1. API client e Vuex

- `app/javascript/dashboard/api/macros.js#executeMacro` — aceitar `{ macroId,
  conversationIds, pipelineItemIds }`, enviando o parâmetro presente.
- Vuex `macros` (`app/javascript/dashboard/store/modules/macros.js`), action `execute` —
  estender de forma equivalente.

## 2. Pontos de entrada no Kanban

- `app/javascript/dashboard/routes/dashboard/kanban/components/KanbanCard.vue` — botão "Rodar
  macro" por card, próximo ao botão de exportar já existente; abre um menu/dropdown pequeno
  (novo componente `KanbanRunMacroMenu.vue`) listando macros com `macro_type ==
  'pipeline_item'`, mirror do list-rendering + botão de play de
  `conversation/Macros/MacroItem.vue`, mas escopado a um único `pipeline_item_id`.
- `app/javascript/dashboard/routes/dashboard/kanban/components/KanbanColumn.vue` — ação em
  lote no cabeçalho da coluna, rodando a macro em todos os cards visíveis daquele estágio
  (verificar antes se já existe alguma seleção múltipla de cards no board; se não existir,
  escopar o "bulk" apenas como "todos os cards do estágio", e tratar seleção múltipla real
  como melhoria futura, fora desta task).
- `app/javascript/dashboard/routes/dashboard/kanban/components/KanbanCardDetail.vue` — ação
  "Rodar macro" no rodapé do painel de detalhe do card.

## 3. Editor de macros

Em `app/javascript/dashboard/routes/dashboard/settings/macros/`:
- Adicionar um seletor de `macro_type` (ex. toggle "Macro de conversa" / "Macro de pipeline")
  no topo de `MacroEditor.vue`/`MacroForm.vue`, controlando qual lista de ações
  `MacroNodes.vue` oferece — mirror de como o prop `isMacro` já ajusta o comportamento do
  componente compartilhado `AutomationActionInput.vue`/`MacroNode.vue`.
- `settings/macros/constants.js` (`MACRO_ACTION_TYPES`) — adicionar as 7 ações de
  `PIPELINE_ACTIONS_ATTRS` (sem `create_pipeline_item`, conforme decidido na task 06),
  reaproveitando os mesmos `inputType`s/componentes compostos criados na task 05 sempre que
  possível (ex. `AutomationActionPipelineStageInput.vue`) em vez de duplicar componentes.
- `useMacros.js#getMacroDropdownValues(action_name)` — branches para as novas ações,
  buscando pipelines/estágios/labels da store do kanban.

## 4. i18n

`app/javascript/dashboard/i18n/locale/en/macros.json` **e** `pt_BR/macros.json` — labels do
seletor de tipo, das 7 ações novas. `kanban.json` (en + pt_BR) — label do botão/menu "Rodar
macro" nos 3 pontos de entrada do item 2.

## Testes / QA

- QA manual: criar uma macro de pipeline com 2-3 ações, rodar a partir de um card específico
  no Kanban, confirmar que as mudanças aparecem (estágio, atribuição, labels conforme a
  macro). Rodar em lote a partir do cabeçalho da coluna.
- Tentar uma ação de `export_pipeline_item` que levaria a um pipeline onde o contato já tem
  card — confirmar que essa ação específica falha silenciosamente (sem crashar o resto da
  macro) e sem quebrar a UI.
- `pnpm eslint:fix` nos arquivos tocados.

## Critério de pronto

- Macro de pipeline criável no editor, com as 7 ações disponíveis.
- 3 pontos de entrada de execução no Kanban funcionando (card, coluna, painel de detalhe).
- i18n completo em en e pt_BR.
