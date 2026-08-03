# Task 15 — Fix: estado obsoleto ao trocar de ação nos inputs compostos de pipeline

Task de correção pós-implementação da task 05. Achado na auditoria de 2026-08-01. Bug de UI
silencioso — o usuário pode salvar uma regra achando que configurou uma ação, mas ela persiste
com `action_params` vazio/incorreto sem nenhum aviso.

## Objetivo

Os componentes compostos de input de pipeline
(`AutomationActionPipelineStageInput.vue`, `AutomationActionPipelineAssigneeInput.vue`,
`AutomationActionPipelineLabelInput.vue`) inicializam seu estado interno (`pipelineId`,
`targetStageId`, `targetPipelineId`, etc.) **só dentro de `mounted()`**, lendo o `modelValue`
recebido naquele momento. Não há nenhum `watch` sobre `modelValue`/`action-name` que resincronize
esse estado depois.

Isso seria inofensivo se cada ação tivesse sua própria instância de componente — mas pares de
ações compartilham o mesmo `inputType` em `AutomationActionInput.vue`:
- `move_pipeline_item_stage` / `export_pipeline_item` → `pipeline_stage_select`
- `assign_pipeline_item_agent` / `assign_pipeline_item_team` → `pipeline_assignee_select`
- `add_pipeline_item_label` / `remove_pipeline_item_label` → `pipeline_label_select`

Em `app/javascript/dashboard/components/widgets/AutomationActionInput.vue`, os `v-if` que
renderizam esses componentes (linhas ~212-233) não têm nenhuma `:key` amarrada ao `action_name` —
só o `<li>` externo na lista de ações (em `AutomationRuleForm.vue`/`MacroNodes.vue`) usa
`:key="i"` (índice), que não muda quando só o `action_name` daquela posição muda. Resultado: ao
trocar o dropdown de ação de, por exemplo, `add_pipeline_item_label` para
`remove_pipeline_item_label` (mesmo `inputType`), o Vue **reutiliza a mesma instância** do
componente em vez de remontar.

`onActionNameChange` (em `AutomationActionInput.vue`) já chama `resetAction()`, que zera o
`action_params` real da ação — mas como o componente filho não remonta e não tem `watch`, seu
estado interno exibido (pipeline/labels selecionados) continua mostrando os valores da ação
anterior, **dessincronizado do `action_params` real** (que já está vazio).

**Cenário de falha concreto:** usuário configura `add_pipeline_item_label` com pipeline P1 +
label "quente"; troca o dropdown de ação para `remove_pipeline_item_label` (mesmo componente).
A UI continua mostrando P1 + "quente" selecionados, mas o `action_params` real já é `[]`. Se
salvar nesse instante, `remove_pipeline_item_label` persiste com `action_params: []` — no
backend, `params = params[0]` vira `nil`, e `params[:labels]` nesse `nil` gera `NoMethodError`
(engolido pelo rescue por-ação): a ação nunca roda, sem qualquer sinal para quem configurou.

## O que corrigir

Escolher uma das duas abordagens (a primeira é mais simples e mais alinhada ao resto do
projeto):

**Opção A — forçar remount via `:key`.** Em `AutomationActionInput.vue`, adicionar uma `:key`
amarrada ao `action_name` (não só ao índice) nos 3 componentes afetados:
```vue
<AutomationActionPipelineStageInput
  v-if="inputType === 'pipeline_stage_select'"
  :key="action_name"
  v-model="action_params"
  ...
```
(mesma ideia para `AutomationActionPipelineAssigneeInput`/`AutomationActionPipelineLabelInput`).
Isso força o Vue a destruir e recriar o componente sempre que o `action_name` mudar, mesmo
dentro do mesmo `inputType` — reexecutando `mounted()` com o `modelValue` (já resetado) correto.

**Opção B — `watch` reativo.** Adicionar em cada um dos 3 componentes um
`watch(() => props.modelValue, (newValue) => { /* reidratar estado interno */ })`, movendo a
lógica hoje em `mounted()` para um método reaproveitável chamado tanto no mount quanto no watch.
Mais código, mas evita destruir/recriar o DOM (sem diferença de UX perceptível aqui, já que a
troca de ação já reseta os valores mesmo).

Recomenda-se a Opção A por ser a menor mudança e não introduzir estado duplicado de
sincronização.

## Testes

- Teste de componente (Vitest) para `AutomationActionInput.vue` ou para um dos 3 componentes
  afetados: montar com `action_name: 'add_pipeline_item_label'` e `modelValue` preenchido, trocar
  `action_name` para `remove_pipeline_item_label` (simulando `resetAction`), e confirmar que o
  estado interno exibido (pipeline/estágio/agente/labels selecionados) reflete o `modelValue`
  vazio, não o anterior.
- QA manual: reproduzir o cenário de falha descrito acima manualmente na tela de Automation
  Rules, confirmando que a UI não mostra mais valores obsoletos após a troca.

## Critério de pronto

- Trocar o `action_name` de uma ação já configurada (dentro do mesmo `inputType`) resincroniza a
  UI corretamente, sem exibir valores da ação anterior.
- Teste de componente cobrindo esse cenário específico.
- Nenhuma regressão no round-trip normal de salvar/reabrir (critério já validado na task 05).
