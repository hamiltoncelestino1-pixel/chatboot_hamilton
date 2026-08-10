# Task 24 — Frontend: expor gatilho nativo de pipeline na tela de automação

Parte do Grupo E ([visão geral](00-visao-geral.md)). Depende da task 23 (ação `send_webhook_event`
de pipeline precisa existir no backend antes de aparecer como opção aqui). Todo o resto do
backend (eventos, listener, filtro de condições, ações) já está implementado desde a task 09 —
esta task é **só frontend**.

## Objetivo

Deixar `pipeline_item_created` e `pipeline_item_stage_changed` escolhíveis como "Event" na tela
de criação/edição de Automation Rule, com condições de `pipeline_id`/`stage_id`/`value`/
`assignee_id`/`team_id`/`labels` e as ações de pipeline já existentes.

## Confirmação do estado atual (investigado)

- `app/javascript/dashboard/routes/dashboard/settings/automation/constants.js`:
  `AUTOMATION_RULE_EVENTS` (linha 849-870) só lista os 5 eventos de conversa; `AUTOMATIONS`
  (linha 8-847) não tem chave `pipeline_item_created`/`pipeline_item_stage_changed`.
- Backend já aceita e valida esses `event_name` livremente (`AutomationRule` não tem enum,
  `app/models/automation_rule.rb`) e já sabe filtrar `conditions` de pipeline via
  `lib/filters/filter_keys.yml` bloco `pipeline_items:` (linhas 247-287, atributos `stage_id`,
  `pipeline_id`, `value`, `assignee_id`, `team_id`, `labels` — mapeado por
  `AutomationRules::PipelineConditionsFilterService::COLUMN_MAP`).
- As 7 ações de pipeline (`move_pipeline_item_stage`, `assign_pipeline_item_agent`,
  `assign_pipeline_item_team`, `add_pipeline_item_label`, `remove_pipeline_item_label`,
  `update_pipeline_item`, `export_pipeline_item`) **já têm** entrada em `AUTOMATION_ACTION_TYPES`
  e componentes prontos (task 05):
  `AutomationActionPipelineStageInput.vue`, `AutomationActionPipelineAssigneeInput.vue`,
  `AutomationActionPipelineLabelInput.vue`, `AutomationActionPipelineUpdateFieldsInput.vue` —
  reaproveitar essas mesmas entradas/componentes, não criar novos. `create_pipeline_item` fica
  de fora (o card já existe quando o evento nativo dispara — mesma decisão do backend,
  `AutomationRules::PipelineActionService` não implementa essa ação).

## 1. `AUTOMATION_RULE_EVENTS`

Adicionar as duas entradas (mesmo formato das 5 existentes, linha 849-870):
```js
{ value: 'pipeline_item_created' },
{ value: 'pipeline_item_stage_changed' },
```

## 2. Novas entradas em `AUTOMATIONS`

```js
pipeline_item_created: {
  conditions: [ /* ver item 3 */ ],
  actions: [ /* ver item 4 */ ],
},
pipeline_item_stage_changed: {
  conditions: [ /* mesmo bloco do item 3 */ ],
  actions: [ /* mesmo bloco do item 4 */ ],
},
```

## 3. Bloco de `conditions` (compartilhado pelos 2 eventos)

```js
[
  {
    key: 'pipeline_id',
    name: 'PIPELINE',
    inputType: 'search_select',
    filterOperators: OPERATOR_TYPES_3,
  },
  {
    key: 'stage_id',
    name: 'STAGE',
    inputType: 'search_select',
    filterOperators: OPERATOR_TYPES_3,
  },
  {
    key: 'value',
    name: 'VALUE',
    inputType: 'plain_text',
    filterOperators: OPERATOR_TYPES_2,
  },
  {
    key: 'assignee_id',
    name: 'ASSIGNEE_NAME',
    inputType: 'search_select',
    filterOperators: OPERATOR_TYPES_3,
  },
  {
    key: 'team_id',
    name: 'TEAM_NAME',
    inputType: 'search_select',
    filterOperators: OPERATOR_TYPES_3,
  },
  {
    key: 'labels',
    name: 'LABELS',
    inputType: 'multi_select',
    filterOperators: OPERATOR_TYPES_3,
  },
]
```
`OPERATOR_TYPES_2`/`OPERATOR_TYPES_3` conforme já usado para `value`/`assignee_id`/`team_id`
em outros eventos (mesmo padrão de `message_created`, linhas 47-58, 60-64).

Fonte de opções de `pipeline_id`: reaproveitar `usePipelineSelector()`
(`app/javascript/dashboard/composables/usePipelineSelector.js`, extraído na task 16) ou o
getter `kanban/getPipelines` diretamente. Fonte de `stage_id`: **decisão de implementação** —
como cada `condition` hoje é uma linha independente no formulário (sem uma linha "saber" o
valor selecionado numa linha irmã), a opção mais simples e de menor risco é listar **todos os
estágios de todos os pipelines da conta**, com label desambiguado (`"<Pipeline> — <Estágio>"`),
em vez de tentar cascatear dinamicamente a partir da condição `pipeline_id` (que exigiria
lógica nova de comunicação entre condition rows, não suportada hoje pelo componente genérico de
condições). Funcionalmente equivalente: o usuário ainda pode combinar as duas conditions
(`pipeline_id = X` E `stage_id = Y`) e o backend já avalia ambas com `AND`.

## 4. Bloco de `actions` (compartilhado pelos 2 eventos)

```js
[
  { key: 'move_pipeline_item_stage', name: 'MOVE_PIPELINE_ITEM_STAGE' },
  { key: 'assign_pipeline_item_agent', name: 'ASSIGN_PIPELINE_ITEM_AGENT' },
  { key: 'assign_pipeline_item_team', name: 'ASSIGN_PIPELINE_ITEM_TEAM' },
  { key: 'add_pipeline_item_label', name: 'ADD_PIPELINE_ITEM_LABEL' },
  { key: 'remove_pipeline_item_label', name: 'REMOVE_PIPELINE_ITEM_LABEL' },
  { key: 'update_pipeline_item', name: 'UPDATE_PIPELINE_ITEM' },
  { key: 'export_pipeline_item', name: 'EXPORT_PIPELINE_ITEM' },
  { key: 'send_webhook_event', name: 'SEND_WEBHOOK_EVENT' },
]
```
As primeiras 7 chaves já existem em `AUTOMATION_ACTION_TYPES` (task 05) — só estão sendo
listadas aqui pela primeira vez para estes 2 eventos novos. `send_webhook_event` já existe como
`inputType` de URL simples (usado hoje pelos eventos de conversa) — reaproveitar o mesmo
componente de input, a ação nova só precisa existir no backend (task 23) para funcionar.

⚠️ Nota de UX conhecida, não bloqueante: os componentes de ação de pipeline (ex.
`AutomationActionPipelineStageInput.vue`) foram construídos na task 05 para o cenário
"evento de conversa → ação de pipeline", onde escolher o `pipeline_id` no `action_params` é
necessário (a automação precisa saber em qual pipeline resolver o card). Nos 2 eventos novos,
o card já é o próprio sujeito do evento — o backend (`AutomationRules::PipelineActionService`)
ignora qualquer `pipeline_id` enviado nesses `action_params`. Reaproveitar o componente como
está (o campo extra fica visualmente redundante, mas inofensivo) é aceitável para esta task;
avaliar se vale a pena esconder o campo via prop (`hidePipelineSelect`) como melhoria incremental
futura, não bloqueante.

## Testes / QA

- Sem suíte de componente automatizada extensa neste módulo hoje — QA manual: criar automação
  em cada um dos 2 eventos novos, configurar `pipeline_id`+`stage_id` como condition, salvar,
  reabrir e confirmar round-trip; mover um card de verdade no Kanban para o estágio configurado
  e confirmar que a ação dispara.
- `pnpm eslint:fix` nos arquivos tocados.

## Critério de pronto

- Os 2 eventos aparecem no dropdown "Event" da tela de Automation Rules.
- Conditions de pipeline configuráveis e persistindo corretamente.
- As 8 ações (7 existentes + `send_webhook_event`) disponíveis e funcionais para os 2 eventos.
