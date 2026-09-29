# Task 12 — Fix: `overdue_tasks_count` ausente do Swagger

Severidade: 🟡 Média. Achado na análise técnica de 2026-08-20 (auditoria pós-`df0251e58`).
Depende da task 04 (o campo precisa estar correto em todas as actions antes de documentar).

## Objetivo

`app/views/api/v1/models/_pipeline_item.json.jbuilder:38` retorna `overdue_tasks_count` — é o
próprio dado que entrega a feature de badge de tarefa vencida do commit `df0251e58`. Confirmado
por busca em todo `swagger/`: `overdue_tasks_count` não aparece em nenhum arquivo, incluindo
`swagger/definitions/resource/pipeline_item.yml` (que o commit editou pra adicionar
`pipeline_lost_reason_id`/`pipeline_lost_reason`, mas não esse campo).

## O que corrigir

Adicionar `overdue_tasks_count` (integer) a `swagger/definitions/resource/pipeline_item.yml`.
Rodar `bundle exec rails swagger:build` depois.

## Testes

Confirmar visualmente no Swagger UI que `overdue_tasks_count` aparece no schema de
`PipelineItem`.

## Critério de pronto

- `overdue_tasks_count` documentado no Swagger.
- `bundle exec rails swagger:build` rodado sem erro.
