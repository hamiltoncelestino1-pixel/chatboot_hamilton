# Task 07 — Macros: job, controller e rota para executar em cards

Parte do Grupo C ([visão geral](00-visao-geral.md)). Depende da task 06
(`Macros::PipelineExecutionService` pronto).

## Objetivo

Expor a execução de macros de pipeline via API, reaproveitando ao máximo o endpoint
`POST /macros/:id/execute` que já existe — sem criar rota nova.

## 1. Novo job: `app/jobs/macros_pipeline_execution_job.rb`

Mirror de `app/jobs/macros_execution_job.rb`:

```ruby
class MacrosPipelineExecutionJob < ApplicationJob
  queue_as :default

  def perform(macro, pipeline_item_ids:, user:)
    account = macro.account
    items = account.pipeline_items.where(id: pipeline_item_ids)
    items.each { |item| ::Macros::PipelineExecutionService.new(macro, item, user).perform }
  end
end
```

**Atenção**: cards não têm `display_id` como conversas — usar `id` direto (diferente de
`MacrosExecutionJob`, que filtra por `display_id`).

## 2. Controller — ramificar `execute` por tipo de alvo

`app/controllers/api/v1/accounts/macros_controller.rb#execute`:

```ruby
def execute
  if params[:pipeline_item_ids].present?
    authorized_ids = policy_scope(Current.account.pipeline_items).where(id: params[:pipeline_item_ids]).pluck(:id)
    ::MacrosPipelineExecutionJob.perform_later(@macro, pipeline_item_ids: authorized_ids, user: Current.user)
  else
    ::MacrosExecutionJob.perform_later(@macro, conversation_ids: params[:conversation_ids], user: Current.user)
  end
  head :ok
end
```

**Ponto de risco — autorização dos itens**: `check_authorization` (before_action já existente
nesse controller) só autoriza o objeto `@macro`, não verifica se o usuário pode agir sobre
cada `pipeline_item_id` recebido. Por isso o `policy_scope` acima é obrigatório — sem ele, um
agente sem acesso a um pipeline poderia rodar uma macro em cards de um pipeline que não
deveria ver (mirror do padrão de autorização já usado em `PipelineItemsController`).

Não é necessária mudança em `config/routes.rb` — a rota `POST /macros/:id/execute` já existe.

## 3. Corrigir strong params (mesmo ponto de risco identificado na task 04)

`app/controllers/api/v1/accounts/macros_controller.rb#permitted_params` hoje é:
```ruby
actions: [:action_name, { action_params: [] }]
```
Array só de escalares — não aceita hash (`{pipeline_id:, target_stage_id:}` etc., necessários
pelas novas ações de pipeline). Aplicar o mesmo ajuste decidido/testado na task 04 (ex.
`action_params: [{}]` ou tratamento manual), e confirmar com teste que os formatos antigos
(ações de conversa com `action_params` array de strings) continuam funcionando.

## Testes

`spec/controllers/api/v1/accounts/macros_controller_spec.rb` (arquivo existente — estender):
- `POST execute` com `pipeline_item_ids` → job `MacrosPipelineExecutionJob` enfileirado com os
  argumentos corretos.
- Enviar um `pipeline_item_id` de um pipeline ao qual o usuário não tem acesso → confirmar que
  é filtrado antes de chegar no job (não aparece em `authorized_ids`).
- `POST execute` com `conversation_ids` (fluxo antigo) continua funcionando sem regressão.

## Critério de pronto

- Endpoint `execute` aceita tanto `conversation_ids` quanto `pipeline_item_ids`, sem rota
  nova.
- Autorização por item confirmada com teste (item não autorizado é filtrado, não gera erro
  nem executa).
- Strong params aceitando o formato hash necessário, com os formatos antigos ainda cobertos
  por teste de regressão.
