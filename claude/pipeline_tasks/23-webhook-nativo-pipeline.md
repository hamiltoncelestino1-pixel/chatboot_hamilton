# Task 23 — Backend: webhook a partir de pipeline (plumbing compartilhado)

Parte do Grupo E ([visão geral](00-visao-geral.md)). Sem dependências dentro deste grupo — é
usada pela task 24 (ação disponível no gatilho nativo) e referenciada pela task 29 (exposição
em macro no frontend), mas o backend desta task funciona sozinho.

## Objetivo

Hoje `send_webhook_event` só existe para conversa (`AutomationRules::ActionService#send_webhook_event`,
`app/services/automation_rules/action_service.rb:41-44`, e
`Macros::ExecutionService#send_webhook_event`, `app/services/macros/execution_service.rb:66-69`).
Criar o equivalente para `PipelineItem`, compartilhado entre automação nativa de pipeline
(task 09, já implementada) e macro de pipeline (task 06, já implementada) — **não** mexe no
model `Webhook`/`ALLOWED_WEBHOOK_EVENTS` (`app/models/webhook.rb:32-34`), que é um sistema de
assinatura global à parte, fora do escopo deste pedido.

## 1. `PipelineItem#webhook_data`

`app/models/pipeline_item.rb` — método público novo, mesmo espírito de
`Conversation#webhook_data` (`app/models/concerns/push_data_helper.rb:12-14`), mas sem
precisar de um presenter dedicado (payload simples, proporcional ao caso de uso):

```ruby
def webhook_data
  {
    id: id,
    title: title,
    value: value,
    notes: notes,
    pipeline_id: pipeline_id,
    pipeline_name: pipeline&.name,
    pipeline_stage_id: pipeline_stage_id,
    pipeline_stage_name: pipeline_stage&.name,
    assignee_id: assignee_id,
    assignee_name: assignee&.name,
    team_id: team_id,
    team_name: team&.name,
    contact_id: contact_id,
    conversation_id: conversation_id,
    created_at: created_at,
    updated_at: updated_at
  }
end
```

Associações já existentes e confirmadas: `pipeline` (delegate, linha 75), `pipeline_stage`,
`assignee`, `team`, `contact` (todas `belongs_to`, linhas 43-53).

## 2. `send_pipeline_webhook_event` no concern compartilhado

`app/services/concerns/pipeline_item_actions.rb` — novo método público, nome deliberadamente
distinto de `send_webhook_event` (mesmo cuidado do resto do arquivo — ver comentário de topo,
linhas 5-7 — para não colidir se este concern algum dia for incluído numa classe que já tem
`send_webhook_event` de outra origem):

```ruby
def send_pipeline_webhook_event(pipeline_item, url_params, event_label)
  return if url_params.blank? || url_params[0].blank?

  payload = pipeline_item.webhook_data.merge(event: event_label)
  WebhookJob.perform_later(url_params[0], payload)
end
```

O rótulo do evento (`event_label`) fica a cargo de quem chama — cada consumidor já tem seu
próprio critério (ver item 3), igual ao que já acontece hoje entre a versão de automação
(`"automation_event.#{@rule.event_name}"`) e a de macro (`'macro.executed'`) do lado de
conversa.

## 3. Wrappers nos dois consumidores

`app/services/automation_rules/pipeline_action_service.rb` — novo método privado, mesmo padrão
dos demais wrappers já existentes no arquivo (`move_pipeline_item_stage`, etc.):
```ruby
def send_webhook_event(params)
  send_pipeline_webhook_event(@pipeline_item, params, "automation_event.#{@rule.event_name}")
end
```

`app/services/macros/pipeline_execution_service.rb` — idem, seguindo a assinatura
`(pipeline_item, params)` já usada pelos outros wrappers deste arquivo:
```ruby
def send_webhook_event(pipeline_item, params)
  send_pipeline_webhook_event(pipeline_item, params, 'macro.executed')
end
```

## 4. Whitelists

- `app/models/automation_rule.rb#actions_attributes` (linha 42-48, bloco de ações de pipeline)
  — adicionar `send_webhook_event`.
- `app/models/macro.rb::PIPELINE_ACTIONS_ATTRS` (linha 43-45) — adicionar `send_webhook_event`.

Não mexer em `CONVERSATION_ACTIONS_ATTRS` — `send_webhook_event` já existe lá apontando para a
implementação de conversa, sem relação com esta task.

## Testes

- `spec/models/pipeline_item_spec.rb` — `#webhook_data` retorna o hash esperado.
- `spec/services/automation_rules/pipeline_action_service_spec.rb` — `send_webhook_event`
  chama `WebhookJob` com a URL e o payload certos (`event: "automation_event.<event_name>"`).
- `spec/services/macros/pipeline_execution_service_spec.rb` — idem, `event: 'macro.executed'`.

## Critério de pronto

- `PipelineItem#webhook_data` implementado e testado.
- `send_webhook_event` disponível e funcional tanto em automação nativa de pipeline quanto em
  macro de pipeline, cada um com seu próprio rótulo de evento.
- `bundle exec rubocop -a` limpo.
