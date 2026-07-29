# Task 05 — Automation Rules: novas ações de pipeline (frontend)

Parte do Grupo B ([visão geral](00-visao-geral.md)). Depende da task 04 (ações já existem no
backend e a API aceita os payloads).

## Objetivo

Deixar as 8 ações de pipeline da task 04 configuráveis pela tela de Automation Rules, com a
mesma qualidade de UX das ações já existentes (ex. atribuir agente, atribuir time).

## 1. Registro das novas ações

`app/javascript/dashboard/routes/dashboard/settings/automation/constants.js`:

- `AUTOMATIONS` — adicionar as 8 novas entradas ao array `actions` de cada bloco de evento
  relevante (`conversation_created`, `conversation_updated`, `conversation_opened`,
  `conversation_resolved`, `message_created`) — mirror do formato já usado
  (`{ key: 'assign_agent', name: 'ASSIGN_AGENT' }` etc.).
- `AUTOMATION_ACTION_TYPES` — adicionar entrada por ação nova, cada uma com um `inputType`
  novo (pois todas precisam de múltiplos campos compostos, não um único select):
  - `create_pipeline_item` → `inputType: 'pipeline_create_item'`
  - `move_pipeline_item_stage` / `export_pipeline_item` → `inputType: 'pipeline_stage_select'`
    (reaproveitar o mesmo componente para os dois, variando só os campos exibidos)
  - `assign_pipeline_item_agent` / `assign_pipeline_item_team` → `inputType:
    'pipeline_assignee_select'`
  - `add_pipeline_item_label` / `remove_pipeline_item_label` → `inputType:
    'pipeline_label_select'`
  - `update_pipeline_item` → `inputType: 'pipeline_update_fields'`

## 2. Novos componentes de input compostos

Mirror direto de
`app/javascript/dashboard/routes/dashboard/settings/automation/AutomationActionTeamMessageInput.vue`
(que já combina um select de time + editor de mensagem num único componente):

- `AutomationActionCreatePipelineItemInput.vue` — select de pipeline → select de estágio (em
  cascata, filtrando estágios pelo pipeline escolhido) + modo de atribuição (radio/select:
  "mesmo agente da conversa" / "sem atribuição" / agente específico) + campos de
  título/valor/notas opcionais.
- `AutomationActionPipelineStageInput.vue` — select de pipeline + select de estágio destino
  (reaproveitado por `move_pipeline_item_stage` e, com um segundo par pipeline+estágio, por
  `export_pipeline_item`).
- `AutomationActionPipelineAssigneeInput.vue` — select de pipeline + select de agente/time.
- `AutomationActionPipelineLabelInput.vue` — select de pipeline + multi-select de labels do
  tipo pipeline daquele pipeline (reaproveitar a lógica de busca de labels já usada em
  `kanban/components/PipelineItemLabels.vue`, se extraível para um composable comum, em vez de
  duplicar a chamada à API).

## 3. Ligar os novos `inputType`s

`app/javascript/dashboard/components/widgets/AutomationActionInput.vue` — adicionar os
`v-else-if` correspondentes aos novos `inputType`s, mirror de como `team_message` já é ligado
a `AutomationActionTeamMessageInput.vue`.

## 4. Fonte de dados (pipelines/estágios/labels)

Os novos componentes precisam de dados de `store/modules/kanban/` (getters de pipelines e
estágios — conferir nomes exatos em `getters.js`). Se a store do kanban ainda não estiver
populada quando a tela de automação carrega, disparar o fetch (`kanban/fetchPipelines` ou
equivalente) no `mounted`/`onMounted` dos novos componentes.

## 5. Geração do payload

`app/javascript/dashboard/helper/automationHelper.js`:
- `getActionOptions()` — adicionar branches para as novas ações apontando para as opções de
  pipeline/estágio/agente/label corretas.
- `getDefaultActions()` — valor padrão sensato ao adicionar uma ação nova pela primeira vez
  (ex. primeiro pipeline disponível pré-selecionado).
- `generateAutomationPayload()` (via `actionQueryGenerator.js`) — confirmar que o formato de
  payload gerado para os novos componentes (hash em `action_params`) é o mesmo já usado por
  `team_message` (`generatePayloadForObject`, que envolve o objeto num array de 1 elemento) —
  não deve precisar de lógica nova aqui se os componentes novos seguirem o mesmo formato de
  dados internos que `AutomationActionTeamMessageInput.vue` já usa.

## 6. i18n

`app/javascript/dashboard/i18n/locale/en/automation.json` **e**
`app/javascript/dashboard/i18n/locale/pt_BR/automation.json` (os dois são mantidos pelo
projeto) — labels das 8 ações, labels/placeholders dos campos dos novos componentes.

## Testes / QA

- Não há suíte de testes de componente Vue automatizada extensa neste módulo hoje — priorizar
  QA manual: criar uma regra em cada um dos 5 eventos com cada uma das 8 ações, salvar,
  reabrir a regra e confirmar que os valores persistem corretamente na UI (round-trip
  completo: salvar → recarregar → os selects mostram o que foi salvo).
- `pnpm eslint:fix` nos arquivos tocados.

## Critério de pronto

- As 8 ações aparecem e são configuráveis na tela de criação/edição de Automation Rule, para
  os 5 eventos existentes.
- Round-trip de salvar/reabrir confirmado manualmente para cada ação.
- i18n completo em en e pt_BR.
