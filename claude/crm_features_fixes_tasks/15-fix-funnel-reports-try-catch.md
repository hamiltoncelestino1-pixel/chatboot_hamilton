# Task 15 — Fix: `fetchReport` do relatório de funil sem tratamento de erro de rede

Severidade: 🟡 Média. Achado na análise técnica de 2026-08-20 (auditoria pós-`df0251e58`).

## Objetivo

`app/javascript/dashboard/routes/dashboard/settings/reports/FunnelReports.vue:32-41`:

```js
const fetchReport = async () => {
  if (!pipelineId.value) return;
  isFetching.value = true;
  try {
    const { data } = await PipelineReportsAPI.getFunnelReport(pipelineId.value);
    report.value = data;
  } finally {
    isFetching.value = false;
  }
};
```

Sem `catch`. Compare com `BotReports.vue:43-60`, que envolve toda chamada de fetch de
relatório em `try { dispatch } catch { useAlert(t('REPORT.DATA_FETCHING_FAILED')) }` — padrão
já estabelecido na tela de Reports. Aqui, se `getFunnelReport` rejeitar (rede, 500), vira uma
unhandled promise rejection; `isFetching` volta a `false` via `finally`, mas `report`
continua `null` e a tela mostra o estado vazio "sem dados suficientes", sem indicar ao usuário
que a requisição de fato falhou (parece só "não há dados", quando na verdade é um erro).

## O que corrigir

Adicionar `catch` chamando `useAlert(t('REPORT.DATA_FETCHING_FAILED'))` (ou chave i18n
equivalente já existente no domínio `report.json`), mesmo padrão de `BotReports.vue`.

## Testes

Testar manualmente: simular falha na API do relatório de funil (ex. desligar o backend
momentaneamente ou forçar erro), confirmar que aparece um toast de erro em vez do estado
silencioso de "sem dados".

## Critério de pronto

- Falha de rede/API no fetch do relatório de funil mostra um toast de erro, mesmo padrão dos
  outros relatórios.
- `pnpm eslint:fix` limpo no arquivo tocado.

## Resultado (2026-10-05)

`catch` adicionado em `fetchReport` (`FunnelReports.vue:30-36`), com `useAlert` importado de
`dashboard/composables` — mesmo caminho usado pelos outros 6 componentes de Reports:

```js
} catch {
  // Dropping the previous report matters when the failure happened while switching
  // pipelines: the select already shows the new pipeline, so keeping the old data would
  // attribute one pipeline's numbers to another. Empty state plus the alert is honest.
  report.value = null;
  useAlert(t('REPORT.DATA_FETCHING_FAILED'));
} finally {
```

**Sem mudança de i18n**: `REPORT.DATA_FETCHING_FAILED` já existe em `en/report.json:7` e
`pt_BR/report.json:7`. `catch` sem binding segue o padrão do projeto (`BotReports.vue:46`,
`SummaryReports.vue:143`).

### Acréscimo ao escopo da task: `report.value = null`

A task pedia só o toast. Limpar o `report` cobre um caso **pior** que o descrito: o usuário
está vendo o funil do pipeline A, troca pro B, a requisição de B falha — e a tela segue
exibindo os números de A enquanto o `SingleSelect` já mostra B, atribuindo os dados de um
pipeline a outro. Dado errado silencioso é mais grave que o estado vazio de que a task
reclama. Aprovado pelo usuário antes de implementar.

### Verificação empírica

Spec temporário (`specs/tmp_funnel_reports_debug.spec.js`, apagado depois) montando o
componente com `shallowMount`, primeiro fetch resolvendo com dados e o segundo (simulando troca
de pipeline) rejeitando:

```
useAlert calls = [["REPORT.DATA_FETCHING_FAILED"]]
✓ alerts and clears the report when the API rejects
Test Files 1 passed | Tests 1 passed
```

Asserções: `useAlert` chamado com a chave certa **e** `wrapper.text()` contendo
`REPORT.NO_ENOUGH_DATA` (prova que o report anterior foi descartado, não só que o toast
apareceu).

**Com o `catch` removido temporariamente**, o mesmo spec falha com `Error: network down`
escapando de `fetchReport` e derrubando o chamador — que no browser é exatamente a unhandled
promise rejection que a task descreve (sem toast, tela mostrando "sem dados suficientes").

### Falso alarme investigado e descartado

A primeira execução do spec acusou um `TypeError: Cannot read properties of undefined (reading
'Lead')` em `avgTimeCollection` (`FunnelReports.vue:85`), que a princípio parecia um segundo bug
(`stage_distribution` presente sem `avg_time_in_stage` derruba o render). **Não é bug**: era a
fixture do spec incompleta. `PipelineReports::FunnelReportBuilder` monta as duas chaves do mesmo
`open_items.group('pipeline_stages.name')` (`funnel_report_builder.rb:32-40`), então as chaves de
`stage_distribution` e `avg_time_in_stage` sempre coincidem — e um grupo cujo `stage_changed_at`
seja todo NULL ainda vem com a chave presente, valor `0.0` via `.transform_values(&:to_f)`.

**Lint:** `eslint` exit 0 e `prettier --check` "All matched files use Prettier code style!".
Arquivo em LF puro (0 bytes CR).
