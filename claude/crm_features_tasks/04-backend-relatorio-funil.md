# Task 04 — Backend: builder + endpoint de relatório de funil

Feature 5 (parte 1 de 2). Depende da task 02 (coluna `stage_changed_at`).

## Objetivo

Expor um endpoint que devolve, por pipeline: valor total em aberto, distribuição de cards
por estágio, e tempo médio no estágio atual (aproximação por snapshot, não histórico
completo — ver nota de escopo abaixo).

## Estado atual (confirmado por leitura de código)

- Não existe `app/controllers/api/v1/accounts/reports_controller.rb` — relatórios vivem em
  `app/controllers/api/v2/accounts/reports_controller.rb`/`summary_reports_controller.rb`,
  autorizados por uma policy única e genérica: `ReportPolicy#view?`
  (`app/policies/report_policy.rb`, só `administrator?`).
- Os builders existentes (`app/builders/v2/reports/base_summary_builder.rb` e afins) são
  fortemente acoplados a `Reports::DataSource`, desenhado só para dimensões de conversa
  (account/agent/inbox/team) — **não dá pra herdar deles**, precisa de builder novo e
  independente.
- `PipelineItem` não usa `paper_trail`/`audited` e não existe tabela de histórico de
  mudança de estágio — confirmado por busca completa no código. O único paralelo do
  produto para esse tipo de agregação é `ReportingEvent`
  (`app/models/reporting_event.rb`), mas replicar esse padrão pra pipeline exigiria
  tabela + listener novos e não teria dado retroativo.

## Nota de escopo (importante, documentar também na resposta da API/UI)

Esta v1 usa a coluna `stage_changed_at` (task 02) como base:
- **Valor total em aberto**: soma de `PipelineItem.value` para cards fora de estágios
  terminais (`won`/`lost`) — dado exato, sem aproximação.
- **Distribuição por estágio**: contagem atual de cards por estágio — é uma "foto" do
  momento, não uma taxa de conversão histórica de verdade (não sabe quantos passaram de
  X pra Y ao longo do tempo).
- **Tempo médio no estágio**: `AVG(now() - stage_changed_at)` só para os cards que ainda
  estão em cada estágio — é "tempo médio dos cards atualmente parados ali", não o tempo
  médio histórico completo de todas as passagens (isso exigiria a tabela de histórico, fora
  do escopo desta v1). **Este texto exato (ou equivalente) precisa aparecer na
  documentação/tooltip do relatório na task 05, para não prometer um dado que o sistema
  não calcula.**

## O que criar

1. `app/builders/pipeline_reports/funnel_report_builder.rb` (nome sugerido):
   ```ruby
   class PipelineReports::FunnelReportBuilder
     pattr_initialize :account, :pipeline

     def build
       {
         open_value: open_value,
         stage_distribution: stage_distribution,
         avg_time_in_stage: avg_time_in_stage
       }
     end

     private

     def open_items
       @open_items ||= pipeline.pipeline_items.joins(:pipeline_stage)
                               .where.not(pipeline_stages: { stage_type: %i[won lost] })
     end

     def open_value
       open_items.sum(:value)
     end

     def stage_distribution
       open_items.joins(:pipeline_stage).group('pipeline_stages.name').count
     end

     def avg_time_in_stage
       open_items.joins(:pipeline_stage)
                 .group('pipeline_stages.name')
                 .average(Arel.sql('EXTRACT(EPOCH FROM (now() - stage_changed_at))'))
     end
   end
   ```
   (ajustar sintaxe exata do `average`/`EXTRACT` durante a implementação, conferir se o
   projeto já tem algum helper de cálculo de duração em segundos usado em outro lugar antes
   de escrever SQL cru novo).
2. Controller novo, ex. `app/controllers/api/v1/accounts/pipelines/funnel_reports_controller.rb`,
   sob rota `GET /api/v1/accounts/:account_id/pipelines/:pipeline_id/funnel_report`.
   Autorização: `authorize :report, :view?` (reaproveitar `ReportPolicy` existente — **não**
   criar uma policy nova, a menos que a decisão abaixo sobre `assigned_pipelines` mude
   isso).
3. **Decisão a confirmar no início da implementação**: `ReportPolicy` hoje é "tudo ou nada"
   pra `administrator?`, sem considerar `assigned_pipelines` (que `PipelinePolicy` já usa
   para restringir quem vê qual pipeline). Duas opções:
   - Seguir a regra existente (só admin vê qualquer relatório, incluindo o de pipeline) —
     mais simples, consistente com o resto do produto.
   - Considerar `assigned_pipelines` também para agentes verem o funil dos pipelines que
     gerenciam — mais correto pro caso de uso, mais trabalho (precisa de lógica nova na
     policy ou no controller).
   Recomendação: seguir a regra existente na v1 (só admin), documentar a limitação, e tratar
   granularidade por pipeline como extensão futura se pedida.
4. Swagger: documentar o endpoint novo (`swagger/paths/`, registrar em
   `swagger/paths/index.yml`, `bundle exec rails swagger:build`) — obrigatório, não
   opcional, conforme regra do projeto.

## Testes

Testar manualmente no Docker local: pipeline com cards em vários estágios e valores
diferentes, confirmar que `open_value`/`stage_distribution`/`avg_time_in_stage` batem com o
que dá pra calcular manualmente olhando os dados. Testar também um card em estágio `lost`
para confirmar que é excluído do cálculo de valor em aberto.

## Critério de pronto

- Endpoint retorna os 3 números corretamente para um pipeline com dados variados.
- Autorização segue `ReportPolicy` existente (só admin).
- Swagger documentado e validado (Skooma não quebra specs de request, se houver).
- `bundle exec rubocop -a` limpo nos arquivos tocados.
