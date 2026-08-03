# Task 16 — Refactor: extrair composable de seleção de pipeline (redundância)

Task de correção/limpeza pós-implementação das tasks 05/08. Achado na auditoria de 2026-08-01.
Não é bug — é uma redundância que vale simplificar antes do merge, já que a própria task 05
pediu esse cuidado (para labels) e ele não foi aplicado ao caso mais repetido (seleção de
pipeline).

## Objetivo

Cinco componentes novos reimplementam quase palavra-por-palavra o mesmo bloco de ~25-30 linhas
para seleção de pipeline:

- `app/javascript/dashboard/components/widgets/AutomationActionCreatePipelineItemInput.vue`
- `app/javascript/dashboard/components/widgets/AutomationActionPipelineStageInput.vue`
- `app/javascript/dashboard/components/widgets/AutomationActionPipelineAssigneeInput.vue`
- `app/javascript/dashboard/components/widgets/AutomationActionPipelineLabelInput.vue`
- `app/javascript/dashboard/components/widgets/AutomationActionPipelineUpdateFieldsInput.vue`

Em todos eles se repete: `pipelines` computed (`kanban/getPipelines`), `pipelineOptions`,
`selectedPipeline` get/set, `watch(pipelines)` para autosseleção do primeiro pipeline disponível,
`mounted()` disparando `kanban/fetchPipelines` se a lista estiver vazia, e
`defaultToFirstPipeline()`. Ver por exemplo `AutomationActionPipelineStageInput.vue` (linhas
25-44, 82-111) como referência do bloco a extrair.

## O que corrigir

Criar um composable `usePipelineSelector()` (local sugerido:
`app/javascript/dashboard/composables/usePipelineSelector.js`) que encapsule:
- fetch-on-mount de pipelines (se ainda não carregados),
- `pipelineOptions` computed,
- um `pipelineId` reativo (ref) com getter/setter de opção selecionada,
- autosseleção do primeiro pipeline disponível quando a lista carrega e nada está selecionado.

Assinatura sugerida:
```js
export function usePipelineSelector(initialPipelineId = null) {
  // retorna { pipelineId, pipelineOptions, selectedPipelineOption, defaultToFirstPipeline }
}
```

Refatorar os 5 componentes acima para consumir esse composable em vez de duplicar a lógica.
Manter o comportamento observável idêntico (nenhuma mudança de UX) — é uma extração pura, sem
alterar o formato do payload gerado por nenhum dos 5 componentes.

Ao refatorar, também avaliar se `AutomationActionPipelineUpdateFieldsInput.vue` (que é
essencialmente um subconjunto de `AutomationActionCreatePipelineItemInput.vue` — pipeline +
título + valor + notas, sem estágio/assignee) deveria continuar como componente separado ou se
vale a pena parametrizar o `CreatePipelineItemInput` (ex. prop `showStageAndAssignee: false`).
Se a extração do composable já reduzir a duplicação a um nível aceitável, não é obrigatório
fundir os dois componentes — decisão de julgamento no momento da implementação, documentar a
escolha no PR.

## Testes

- Testes de componente existentes (se houver) para os 5 componentes devem continuar passando
  sem alteração de asserções — a refatoração não muda comportamento observável.
- Se não houver testes de componente hoje para esses arquivos, não é obrigatório criá-los nesta
  task (fora do escopo — é refactor, não nova funcionalidade); mas QA manual do round-trip
  salvar/reabrir (já pedido na task 05) deve ser reconfirmado após a extração.

## Critério de pronto

- `usePipelineSelector()` criado e reaproveitado pelos 5 componentes, sem lógica de seleção de
  pipeline duplicada entre eles.
- Nenhuma mudança de comportamento observável (payload gerado, round-trip salvar/reabrir,
  autosseleção do primeiro pipeline) — só redução de duplicação.
- `pnpm eslint:fix` nos arquivos tocados.
