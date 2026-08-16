# Task 05 — Frontend: página de relatório de funil

Feature 5 (parte 2 de 2). Depende da task 04 (endpoint de backend).

## Objetivo

Página exibindo os 3 números do relatório de funil (valor em aberto, distribuição por
estágio, tempo médio no estágio) para um pipeline selecionado.

## Estado atual (confirmado por leitura de código)

- Frontend de relatórios fica em `app/javascript/dashboard/routes/dashboard/settings/reports/`.
- Biblioteca de gráfico: `chart.js` + `vue-chartjs`, via wrapper
  `app/javascript/shared/components/charts/BarChart.vue`.
- Componentes reutilizáveis: `ReportMetricCard.vue` (card de métrica label+valor),
  `ReportHeader.vue`, `ReportFilters.vue` (seletor de período/dimensão),
  `ReportsWrapper.vue`/`ReportContainer.vue` (layout).
- Rotas de relatório protegidas por `meta: { featureFlag: FEATURE_FLAGS.REPORTS, permissions:
  ['administrator', 'report_manage'] }` — nota: o backend (`ReportPolicy`) só libera
  `administrator?`, então uma conta com `report_manage` mas sem `administrator` veria a rota
  mas receberia 403 do endpoint novo. Não é uma regressão desta task (já é assim para os
  relatórios existentes) — só não piorar a inconsistência introduzindo um caminho de UI que
  finge suportar `report_manage` sem realmente suportar.

## O que criar

1. Decidir onde a página encaixa na navegação: aba nova dentro da tela de relatórios
   existente (`routes/dashboard/settings/reports/`) ou uma seção dentro da própria tela do
   Kanban (`routes/dashboard/kanban/`) com um seletor de pipeline. Recomendação: dentro de
   relatórios existentes, para reaproveitar o layout/navegação já pronta
   (`ReportsWrapper.vue`) sem duplicar chrome de página.
2. Seletor de pipeline (a métrica é por pipeline, não agregada de todos) — reaproveitar o
   composable `usePipelineSelector` (`app/javascript/dashboard/composables/usePipelineSelector.js`,
   já consolidado conforme `claude/pipeline_tasks/16-*.md`) em vez de inventar um seletor
   novo.
3. `ReportMetricCard.vue` para "valor total em aberto".
4. `BarChart.vue` para distribuição de cards por estágio (eixo X = nome do estágio, eixo Y
   = contagem) e para tempo médio por estágio (eixo Y = dias, com um tooltip/nota explicando
   que é o tempo dos cards atualmente no estágio, não histórico — ver nota de escopo da
   task 04, reproduzir o mesmo aviso na UI).
5. API client novo: `app/javascript/dashboard/api/pipelineReports.js` (ou método adicional
   em `api/pipelines.js`), seguindo o padrão `class XyzAPI extends ApiClient`.
6. i18n: chaves novas no domínio de relatórios existente (conferir se `reports.json` ou
   equivalente já existe para strings de relatório, e se esse domínio está na exceção
   kanban/automation/macros do `CLAUDE.md` — provavelmente não está, então só `en`).

## Testes

Testar manualmente no Docker local (navegador): abrir a página como admin, selecionar
diferentes pipelines, confirmar que os números batem com o backend (task 04) e que o
gráfico renderiza corretamente com pipelines vazios (sem cards) sem quebrar.

## Critério de pronto

- Página acessível só por admin (consistente com `ReportPolicy` do backend).
- Números e gráficos corretos para pelo menos 2 pipelines de teste diferentes.
- Aviso visível de que "tempo médio por estágio" é uma aproximação por snapshot.
- `pnpm eslint:fix` limpo nos arquivos tocados.
