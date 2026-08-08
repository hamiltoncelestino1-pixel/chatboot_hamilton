# Task 29 — Frontend + i18n: expor ações cruzadas de macro

Parte do Grupo E ([visão geral](00-visao-geral.md)). Depende das tasks 26 e 27 (as ações
precisam existir no backend antes de aparecer na UI) e da task 23 (webhook nativo de pipeline).

## Objetivo

Deixar as ações novas (macro de conversa → pipeline, macro de pipeline → conversa, webhook
nativo de pipeline) configuráveis pela tela de edição de macro, com a mesma qualidade de UX das
ações já existentes.

## 1. `routes/dashboard/settings/macros/constants.js`

- `MACRO_ACTION_TYPES` (linha 1-77, ações de macro de conversa) — adicionar as 8 entradas de
  pipeline da task 26 (`create_pipeline_item`, `move_pipeline_item_stage`,
  `assign_pipeline_item_agent`, `assign_pipeline_item_team`, `add_pipeline_item_label`,
  `remove_pipeline_item_label`, `update_pipeline_item`, `export_pipeline_item`) — reaproveitar
  os mesmos `inputType`s já usados nas ações de pipeline de `AUTOMATION_ACTION_TYPES`
  (`automation/constants.js`), incluindo `pipeline_create_item` para `create_pipeline_item`
  (único que precisa dele — as automações não têm essa ação em `PIPELINE_ACTION_TYPES`, mas o
  `inputType`/componente de automação `AutomationActionCreatePipelineItemInput.vue`, task 05,
  já cobre o formato de payload igual, é reaproveitável).
- `PIPELINE_MACRO_ACTION_TYPES` (linha 81-117, ações de macro de pipeline) — adicionar:
  - As 15 ações de conversa da task 27 (`send_message`, `add_label`, `assign_team`,
    `assign_agent`, `mute_conversation`, `change_status`, `remove_label`,
    `remove_assigned_agent`, `remove_assigned_team`, `resolve_conversation`,
    `snooze_conversation`, `change_priority`, `send_email_transcript`, `send_attachment`,
    `add_private_note`) — reaproveitar os `inputType`s já usados em `MACRO_ACTION_TYPES` para
    essas mesmas chaves (são literalmente as mesmas ações, só disponíveis agora também na lista
    de pipeline).
  - `send_webhook_event` (task 23) — mesmo `inputType` de URL já usado em `MACRO_ACTION_TYPES`
    para a versão de conversa.

## 2. `MacroEditor.vue` / `MacroNode.vue` / `MacroForm.vue`

Nenhuma mudança de lógica esperada — `macroActionTypes` (computed em `MacroEditor.vue:38-46`)
já escolhe a lista certa por `macro.macro_type` e faz `provide`; `MacroNode.vue` já consome via
`inject`. As listas só ficam maiores. Conferir especificamente:
- `MacroForm.vue:75-89` (`defaultActionNameFor`/`updateMacroType`) — o default ao trocar de tipo
  continua sendo `move_pipeline_item_stage` (pipeline) / `assign_team` (conversa), não precisa
  mudar; só confirmar que resetar para esse default continua funcionando com as listas maiores.
- Filtros por tela (`KanbanRunMacroMenu.vue:24-25`, `conversation/Macros/List.vue`) — não
  mudam, continuam filtrando por `macro.macro_type`, independente de quantas ações cada tipo
  tem agora.

## 3. i18n — `macros.json` (en + pt_BR, ambos obrigatórios)

`app/javascript/dashboard/i18n/locale/en/macros.json` e `pt_BR/macros.json`:
- Ações de pipeline (linhas 118-124, já existem desde a task 06) — nada novo aqui, são
  reaproveitadas por `MACRO_ACTION_TYPES` agora.
- Ações de conversa (já existem desde antes da task 06) — idem, reaproveitadas por
  `PIPELINE_MACRO_ACTION_TYPES` agora.
- Única chave genuinamente nova (se ainda não existir): rótulo/placeholder de `send_webhook_event`
  quando usado no contexto de pipeline, se for necessário um texto diferente do já usado para
  conversa (ex. "Send a webhook with this card's data" vs "Send a webhook with this
  conversation's data") — avaliar na implementação se o texto genérico já existente serve, ou
  se vale diferenciar.

## Testes / QA

- Sem suíte de componente automatizada extensa neste módulo — QA manual: criar um macro de
  conversa com uma ação de pipeline (ex. `move_pipeline_item_stage`) e executar contra uma
  conversa com card vinculado; criar um macro de pipeline com uma ação de conversa (ex.
  `add_label`) e executar contra um card com conversa vinculada; confirmar round-trip
  salvar/reabrir para as novas ações nos dois tipos.
- `pnpm eslint:fix` nos arquivos tocados.

## Critério de pronto

- As ações cruzadas (tasks 26/27) e o webhook nativo (task 23) aparecem e são configuráveis nos
  dois tipos de macro, pela UI.
- Round-trip de salvar/reabrir confirmado manualmente.
- i18n completo em en e pt_BR.
