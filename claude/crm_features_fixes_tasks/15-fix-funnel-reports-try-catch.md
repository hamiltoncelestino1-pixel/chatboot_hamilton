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
