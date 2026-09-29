# Task 11 — Fix: `stale_alert_days` ausente do Swagger

Severidade: 🟡 Média. Achado na análise técnica de 2026-08-20 (auditoria pós-`df0251e58`).

## Objetivo

`app/models/pipeline.rb:11` define o campo, `app/controllers/api/v1/accounts/pipelines_controller.rb:32-34`
aceita no `pipeline_params`, `app/views/api/v1/models/_pipeline.json.jbuilder:10` retorna na
resposta. Confirmado por busca em todo `swagger/`: `stale_alert_days` não aparece em nenhum
arquivo — nem em `swagger/definitions/resource/pipeline.yml` nem em
`swagger/definitions/request/pipeline/create_update_payload.yml`. O commit `df0251e58` (que
introduziu o campo) não tocou nenhum dos dois YAMLs.

## O que corrigir

Adicionar `stale_alert_days` (integer, nullable) a:
- `swagger/definitions/resource/pipeline.yml` (campo de resposta)
- `swagger/definitions/request/pipeline/create_update_payload.yml` (campo aceito em
  create/update)

Rodar `bundle exec rails swagger:build` depois de editar os YAMLs (regra de memória do
projeto: nova tag/campo exige esse passo pra aparecer corretamente no Swagger UI e nas specs
validadas por Skooma).

## Testes

Confirmar visualmente no Swagger UI que `stale_alert_days` aparece no schema de `Pipeline` e
no payload de create/update de Pipeline. Se houver specs de request pra `PipelinesController`,
rodar (`bundle exec rspec spec/requests/api/v1/accounts/pipelines_controller_spec.rb`, se
existir) pra confirmar que o Skooma não acusa divergência.

## Critério de pronto

- `stale_alert_days` documentado no Swagger, coerente com o que a API de fato aceita/retorna.
- `bundle exec rails swagger:build` rodado sem erro.
