# Task 13 — Cron de "card parado" sem índice que sirva

Severidade: 🟢 Baixa. Achado na análise de performance de 2026-09-15.
Independente das demais.

## Objetivo

`app/jobs/pipeline_items/trigger_stale_items_job.rb:21-31`:

```ruby
def stale_items(pipeline)
  pipeline.pipeline_items
          .joins(:pipeline_stage)
          .where.not(pipeline_stages: { stage_type: [:won, :lost] })
          .where(stale_alert_sent_at: nil)
          .where.not(assignee_id: nil)
          .where('stage_changed_at < ?', pipeline.stale_alert_days.days.ago)
end
```

Roda para cada pipeline com `stale_alert_days` configurado (`:5`). Os índices existentes em
`pipeline_items` (`db/schema.rb:1095-1105`) cobrem `pipeline_id`, `pipeline_stage_id`,
`assignee_id`, etc., mas **nenhum** cobre `stale_alert_sent_at` ou `stage_changed_at`. Com
muitos cards, o Postgres filtra por `pipeline_id` pelo índice e depois varre todas as linhas
do pipeline para aplicar as outras três condições, a cada execução do cron.

Impacto real é menor que o das outras tasks — é um job de fundo, não o request do agente — mas
é carga periódica no mesmo banco que atende o board, e o custo cresce junto com o volume.

O projeto já tem o padrão certo para exatamente este formato de consulta, em `tasks`
(`db/schema.rb:1331`):

```ruby
t.index ["due_date"], name: "index_tasks_on_due_date_pending_reminder",
        where: "((completed_at IS NULL) AND (reminder_sent_at IS NULL))"
```

Índice parcial: a coluna que ordena/compara no `index`, as condições de "ainda não processado"
no `WHERE`.

## O que corrigir

1. Migration com um índice parcial em `pipeline_items`, no mesmo formato: `stage_changed_at`
   indexado, com `where: 'stale_alert_sent_at IS NULL AND assignee_id IS NOT NULL'`.
   Incluir `pipeline_id` no índice se o `EXPLAIN` mostrar que ajuda — decidir pelo plano real,
   não por intuição.
2. Rodar a migration e comparar `EXPLAIN ANALYZE` da query antes e depois, com volume semeado.
   Se o plano não mudar, **não** commitar o índice: índice que não é usado é só custo de
   escrita em toda movimentação de card (e `touch_stage_changed_at`,
   `app/models/pipeline_item.rb:193-197`, escreve nessas colunas com frequência).
3. Atualizar `db/schema.rb` (gerado pela migration) e o comentário de anotação no topo de
   `app/models/pipeline_item.rb:24-36`, que lista os índices — a gem de anotação atualiza
   sozinha, mas conferir que o diff saiu.

## Testes

1. Semear alguns milhares de cards num pipeline com `stale_alert_days` configurado.
2. `EXPLAIN ANALYZE` da query de `stale_items` antes e depois — registrar os dois planos na
   task. Critério: index scan em vez de seq scan, e tempo menor.
3. Rodar o job manualmente (`PipelineItems::TriggerStaleItemsJob.perform_now` no console) e
   confirmar que os mesmos cards são notificados que antes — o índice não pode mudar o
   resultado, só o caminho.
4. Confirmar que mover um card (que escreve `stage_changed_at` e zera `stale_alert_sent_at`)
   continua rápido — é o lado do custo de escrita do índice.

## Critério de pronto

- Índice parcial criado **e comprovadamente usado** pelo plano de execução (ou descartado com
  a justificativa registrada aqui).
- Resultado do job idêntico ao de antes.
- `db/schema.rb` e a anotação do model atualizados.
- `bundle exec rubocop -a` limpo na migration.

## Resultado (2026-09-16)

Índice criado: `index_pipeline_items_on_stage_changed_at_pending_stale_alert` em
`stage_changed_at`, `where: 'stale_alert_sent_at IS NULL AND assignee_id IS NOT NULL'`
(migration `20260916140000`). **Sem `pipeline_id`** no índice: a query não filtra por
`pipeline_items.pipeline_id` diretamente (filtra por `pipeline_stages.pipeline_id` via join),
então uma coluna a mais no índice não seria usada por este SQL sem reescrever o finder — fora do
escopo desta task.

Medido no Docker local com 50.000 `pipeline_items` num único pipeline/stage, distribuição
realista (90% com `assignee_id`, 90% já com `stale_alert_sent_at`, 50% com `stage_changed_at`
antigo) → 2204 cards realmente elegíveis (4,4%):

- **Antes**: `Index Scan` em `index_pipeline_items_on_pipeline_stage_id`, varrendo as 50.000
  linhas da stage e descartando 47.796 via `Filter` — 9.04ms.
- **Depois**: `BitmapAnd` entre o índice novo e `index_pipeline_items_on_pipeline_stage_id` — 3.18ms.
- Plano mudou (índice novo aparece no `BitmapAnd`) e ficou ~65% mais rápido. Índice mantido.

Rodei `PipelineItems::TriggerStaleItemsJob.perform_now` de verdade (não só `EXPLAIN`): notificou
exatamente os 2204 itens esperados, 0 restantes depois — resultado idêntico ao pré-índice (é a
mesma query ActiveRecord, só muda o plano).

Custo de escrita: 100 updates em `stage_changed_at`/`stale_alert_sent_at` do mesmo registro,
1.76ms/write em média — sem degradação perceptível.

`db/schema.rb` e a anotação de `pipeline_item.rb` atualizados automaticamente pela migration.
Dados de benchmark (50k contatos/cards, pipeline de teste) removidos depois da medição.
