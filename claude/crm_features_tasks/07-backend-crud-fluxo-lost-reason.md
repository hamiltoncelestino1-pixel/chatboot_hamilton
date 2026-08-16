# Task 07 — Backend: CRUD de motivos + validação no fluxo de update de card

Feature 2 (parte 2 de 3). Depende da task 06.

## Objetivo

Expor CRUD de `PipelineLostReason` pra Configurações, e permitir que
`PipelineItemsController#update` receba `pipeline_lost_reason_id`.

## O que criar

1. `app/policies/pipeline_lost_reason_policy.rb` — seguir o padrão de policy de recurso
   simples `belongs_to :account` já usado no projeto (conferir `CannedResponsePolicy` ou
   equivalente como referência mais próxima; provavelmente `create?`/`update?`/`destroy?`
   restritos a admin, mesmo critério de outras listas de configuração).
2. `app/controllers/api/v1/accounts/pipeline_lost_reasons_controller.rb` — CRUD simples
   (`index`, `create`, `update`, `destroy`), mesmo formato de
   `PipelinesController`/`PipelineStagesController` (sem aninhamento em pipeline, já que o
   motivo é por conta, não por pipeline).
3. Rotas em `config/routes.rb`, sob `Api::V1::Accounts` — `resources :pipeline_lost_reasons`.
4. Views Jbuilder: `app/views/api/v1/accounts/pipeline_lost_reasons/*.json.jbuilder` +
   partial `app/views/api/v1/models/_pipeline_lost_reason.json.jbuilder`.
5. `PipelineItemsController#update_params`
   (`app/controllers/api/v1/accounts/pipeline_items_controller.rb:115-121`) — adicionar
   `:pipeline_lost_reason_id` ao `permit`.
6. Swagger: documentar os endpoints novos (`swagger/paths/`, registrar em
   `swagger/paths/index.yml`, `bundle exec rails swagger:build`).

## Testes

Testar manualmente: criar/editar/remover motivos via API (Postman/curl ou Docker local),
confirmar unicidade por conta (mesmo título em contas diferentes é permitido, na mesma
conta não), confirmar que `PipelineItemsController#update` aceita e persiste
`pipeline_lost_reason_id`.

## Critério de pronto

- CRUD funcional e autorizado só para admin.
- `PipelineItemsController#update` aceita o novo campo.
- Swagger documentado, specs de request (se houver) batendo via Skooma.
- `bundle exec rubocop -a` limpo nos arquivos tocados.
