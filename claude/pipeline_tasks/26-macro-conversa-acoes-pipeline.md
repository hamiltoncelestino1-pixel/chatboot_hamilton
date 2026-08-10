# Task 26 — Backend: macro de conversa executando ações de pipeline

Parte do Grupo E ([visão geral](00-visao-geral.md)). Sem dependência das tasks 22-25. Depende
conceitualmente das tasks 04/06 (já implementadas — é onde vive o código a extrair).

## Objetivo

Permitir que um macro `macro_type: conversation` execute as mesmas 8 ações de pipeline que uma
automação disparada por evento de conversa já executa hoje
(`AutomationRules::ActionService`), reaproveitando literalmente a mesma lógica em vez de
duplicá-la.

## Por que extrair um concern (e não reimplementar)

`AutomationRules::ActionService` (`app/services/automation_rules/action_service.rb`) já resolve
exatamente o mesmo problema — "a partir de uma conversa, criar/mover/atribuir/rotular/atualizar/
exportar um card de pipeline" — nas linhas 71-176 (métodos `create_pipeline_item`,
`move_pipeline_item_stage`, `assign_pipeline_item_agent`, `assign_pipeline_item_team`,
`add_pipeline_item_label`, `remove_pipeline_item_label`, `update_pipeline_item`,
`export_pipeline_item`, `resolve_pipeline_item_for_conversation`,
`resolve_pipeline_item_assignee_id`, `resolve_pipeline_item_team_id`, `log_no_pipeline_item`,
`log_invalid_target_stage`). Todos esses métodos já usam só `@account`/`@conversation`
(ivars) e os métodos do concern `PipelineItemActions` já incluído
(`move_stage`, `assign_pipeline_agent`, etc.) — nenhuma dependência de `@rule`. `Macros::ExecutionService`
(`app/services/macros/execution_service.rb`) tem exatamente os mesmos ivars (`@account`,
`@conversation`, setados em `initialize`/`super`), então o bloco inteiro é reaproveitável sem
adaptação de assinatura.

## 1. Extrair `ConversationPipelineActions`

Novo arquivo `app/services/concerns/conversation_pipeline_actions.rb` — mover (não duplicar) as
linhas 71-176 de `automation_rules/action_service.rb` para dentro do módulo:

```ruby
module ConversationPipelineActions
  def create_pipeline_item(params)
    # ...corpo idêntico ao atual (action_service.rb:71-85)
  end

  def move_pipeline_item_stage(params)
    # ...idêntico (linha 87-94)
  end

  # assign_pipeline_item_agent, assign_pipeline_item_team, add_pipeline_item_label,
  # remove_pipeline_item_label, update_pipeline_item, export_pipeline_item — idem, corpo
  # idêntico ao atual.

  private

  def resolve_pipeline_item_for_conversation(pipeline_id)
    # ...idêntico (linha 145-147)
  end

  # resolve_pipeline_item_assignee_id, resolve_pipeline_item_team_id, log_no_pipeline_item,
  # log_invalid_target_stage — idem.
end
```

## 2. `app/services/automation_rules/action_service.rb`

Remover o bloco movido (linhas 71-176), adicionar `include ConversationPipelineActions` junto
ao `include PipelineItemActions` já existente (linha 2). Nenhuma outra mudança neste arquivo —
comportamento deve ser idêntico ao de antes da extração.

## 3. `app/services/macros/execution_service.rb`

```ruby
class Macros::ExecutionService < ActionService
  include PipelineItemActions
  include ConversationPipelineActions
  # ...resto do arquivo sem mudança
```

## 4. Whitelist

`app/models/macro.rb::CONVERSATION_ACTIONS_ATTRS` (linha 35-38) — adicionar as 8 ações de
pipeline, espelhando exatamente `AutomationRule#actions_attributes`
(`app/models/automation_rule.rb:42-48`):
```ruby
CONVERSATION_ACTIONS_ATTRS = %w[send_message add_label assign_team assign_agent mute_conversation change_status remove_label
                                remove_assigned_agent remove_assigned_team resolve_conversation snooze_conversation
                                change_priority send_email_transcript send_attachment add_private_note
                                send_webhook_event create_pipeline_item move_pipeline_item_stage
                                assign_pipeline_item_agent assign_pipeline_item_team add_pipeline_item_label
                                remove_pipeline_item_label update_pipeline_item export_pipeline_item].freeze
```

Ao contrário do macro de pipeline (task 06, que deliberadamente excluiu `create_pipeline_item`
porque o card já existe), aqui `create_pipeline_item` faz sentido — o macro roda sobre uma
conversa que pode ainda não ter card em determinado pipeline, mesmo cenário que já vale para
automação (`AutomationRules::ActionService`).

## Risco: reversão de decisão deliberada

`macro.rb:40-42` documenta explicitamente a separação rígida por `macro_type`. Esta task não
remove a separação (macro continua sendo ou `conversation` ou `pipeline_item`, nunca os dois) —
só amplia o que um macro de conversa pode fazer, mantendo o mecanismo de whitelist por
`macro_type` intacto. `MacroForm.vue`/`MacroEditor.vue` (reset de `actions` ao trocar
`macro_type`) não precisam de mudança de lógica, só de dados novos vindos de `constants.js`
(task 29).

## Testes

- `spec/services/automation_rules/action_service_spec.rb` (existente) — rodar sem alteração de
  asserções depois da extração, confirmando que a refatoração não mudou comportamento.
- `spec/services/concerns/conversation_pipeline_actions_spec.rb` (novo, se for o padrão adotado
  pela task 06 para `pipeline_item_actions_spec.rb`) ou testar via os dois consumidores.
- `spec/services/macros/execution_service_spec.rb` — um exemplo por ação de pipeline nova,
  incluindo `create_pipeline_item` falhando por duplicidade (contato já tem card no pipeline) e
  confirmando que só aquela ação é pulada (rescue por-ação já existente em
  `Macros::ExecutionService#perform`, linha 15-17).

## Critério de pronto

- `ConversationPipelineActions` extraído e reaproveitado pelos dois services, zero lógica
  duplicada.
- Specs de `automation_rules/action_service_spec.rb` continuam passando sem alteração.
- Macro de conversa consegue criar/mover/atribuir/rotular/atualizar/exportar card de pipeline.
- `bundle exec rubocop -a` limpo.
