# Task 07 — Fix: fetch duplicado no carregamento inicial do relatório de funil

Severidade: 🟠 Alta. Achado na análise técnica de 2026-08-20 (auditoria pós-`df0251e58`).

## Objetivo

`app/javascript/dashboard/routes/dashboard/settings/reports/FunnelReports.vue:43-44`:

```js
onAutoSelect(fetchReport);      // linha 43
watch(pipelineId, fetchReport); // linha 44
```

`usePipelineSelector.js` (`onAutoSelect`) já existe justamente pra reagir à auto-seleção do
primeiro pipeline disponível. **Todos os outros 4 consumidores** desse composable
(`AutomationActionCreatePipelineItemInput.vue:32`, `AutomationActionPipelineStageInput.vue`,
`AutomationActionPipelineAssigneeInput.vue`, `AutomationActionPipelineUpdateFieldsInput.vue`)
usam **apenas** `onAutoSelect(callback)`, sem combinar com um `watch` adicional no mesmo valor.

Como `watch()` do Vue é agendado (não síncrono), quando `defaultToFirstPipeline()`
(`usePipelineSelector.js:36-40`) seta `pipelineId.value = ...` e, na sequência **síncrona**,
chama `autoSelectCallback()` (= `fetchReport`), o `watch(pipelineId, fetchReport)` também
dispara depois, pra essa mesma mudança de valor — causando uma **segunda chamada** a
`fetchReport`.

**Efeito**: `GET /pipelines/:id/funnel_report` é disparado duas vezes toda vez que o usuário
abre "Reports > Funnel" sem pipeline pré-selecionado (praticamente toda primeira visita) —
mesmo padrão de dispatch duplicado que a auditoria de 2026-08-16 já corrigiu no board Kanban
(`claude/crm_optimizacao_tasks/08-*.md`).

## O que corrigir

Remover o `watch(pipelineId, fetchReport)` redundante — `onAutoSelect(fetchReport)` já cobre a
auto-seleção inicial. Se o objetivo era também refazer o fetch quando o usuário **troca
manualmente** de pipeline no seletor, confirmar como os outros 4 consumidores resolvem esse
caso (ex. o próprio seletor pode disparar um evento de change tratado separadamente) e seguir
o mesmo padrão, em vez de duplicar reatividade sobre o mesmo valor.

## Testes

Testar manualmente com o Network tab aberto: abrir "Reports > Funnel" pela primeira vez (sem
pipeline selecionado antes) — `GET /pipelines/:id/funnel_report` deve disparar uma única vez.
Trocar manualmente de pipeline no seletor — o relatório deve atualizar corretamente.

## Critério de pronto

- Abrir a tela de relatório de funil dispara exatamente 1 request de fetch do relatório.
- Trocar de pipeline manualmente continua atualizando o relatório corretamente.
- `pnpm eslint:fix` limpo no arquivo tocado.

## Resultado (2026-09-29)

A pergunta que a task deixava em aberto ("como os outros consumidores resolvem a troca manual?")
tem resposta clara no código: **todos os 5** chamam, no `set` do computed do seletor, o mesmo
callback que passaram ao `onAutoSelect`. Ver `AutomationActionPipelineStageInput.vue:84-95`:

```js
set: option => {
  pipelineId.value = option?.id || null;
  if (!isExport.value) targetStageId.value = null;
  updateValue();            // o mesmo callback do onAutoSelect(updateValue)
},
```

Nenhum deles usa `watch` no `pipelineId` — o `FunnelReports` era o único fora do padrão, e era
exatamente o que duplicava o fetch. Então a correção é alinhar ao padrão, não inventar um terceiro
caminho:

1. `watch(pipelineId, fetchReport)` removido.
2. `fetchReport()` chamado no `set` do computed `selectedPipeline` (que é o `v-model` do
   `SingleSelect`, ou seja, o caminho real da troca manual).
3. `watch` removido do import do `vue` (ficou sem uso; era o único uso no arquivo).
4. `fetchReport` movido para **antes** do computed — o ESLint deste projeto trata
   `no-use-before-define` como **erro**, não warning. O runtime funcionaria (a closure resolve na
   chamada), mas a regra proíbe, e os consumidores irmãos também declaram o callback antes.

**Verificação:** não existe spec para este componente. Usei o recurso da task 30 de
`claude/pipeline_performance_tasks/`: spec Vitest temporário (`tmp-funnel-fetch.spec.js`,
apagado depois) com `shallowMount`, mockando `pipelineReports`, `dashboard/composables/store`,
`vue-i18n` e `useNumberFormatter`, exercitando o caminho real de abertura (a lista de pipelines
resolvendo → `defaultToFirstPipeline`).

| Cenário | Código antigo | Com a correção |
|---|---|---|
| Abrir a tela (auto-seleção) | ❌ `expected "spy" to be called 1 times, but got 2 times` | ✅ 1 chamada, com o id certo |
| Trocar de pipeline manualmente | ✅ passava (era o `watch` que cobria) | ✅ continua passando (agora via `set`) |

O segundo cenário é o que importa como não-regressão: era o `watch` removido que sustentava a
troca manual, então o spec confirma que o `set` assumiu esse papel sem lacuna.

**ESLint:** limpo no arquivo (0 erros, 0 warnings). O erro `no-use-before-define` apareceu na
primeira tentativa e foi o que motivou a reordenação do item 4.

**Nota sobre `git status`:** o diretório `settings/reports/` inteiro aparece como modificado, mas
`git diff --stat` mostra **só** `FunnelReports.vue` com diff real. É o mesmo cache de stat do git
já diagnosticado na segunda auditoria de `claude/pipeline_performance_tasks/` — não é
renormalização de line ending nem alteração acidental.
