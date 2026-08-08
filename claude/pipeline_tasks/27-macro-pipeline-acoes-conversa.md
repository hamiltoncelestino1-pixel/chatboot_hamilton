# Task 27 — Backend: macro de pipeline executando ações na conversa vinculada

Parte do Grupo E ([visão geral](00-visao-geral.md)). Depende da task 23 (para não colidir o
nome `send_webhook_event` — ver nota abaixo). Independente das tasks 26/28.

## Objetivo

Permitir que um macro `macro_type: pipeline_item` execute ações sobre a `Conversation`
vinculada ao card (`pipeline_item.conversation`, `belongs_to :conversation, optional: true`,
`app/models/pipeline_item.rb:46`), reaproveitando as ações já implementadas e testadas em
`Macros::ExecutionService` em vez de reimplementá-las.

## Mecanismo: delegar para `Macros::ExecutionService`, não duplicar lógica

`Macros::ExecutionService` (`app/services/macros/execution_service.rb`) já implementa todas as
ações de conversa (herdadas de `ActionService` + `send_message`/`add_private_note`/
`send_attachment` próprias). Em vez de recriar essa lógica em `Macros::PipelineExecutionService`
(que não herda de `ActionService` de propósito — comentário no topo do arquivo), instanciar
`Macros::ExecutionService` apontando para a conversa vinculada e delegar a chamada da ação
única:

```ruby
# app/services/macros/pipeline_execution_service.rb
private

CONVERSATION_ACTIONS = %w[send_message add_label assign_team assign_agent mute_conversation
                          change_status remove_label remove_assigned_agent remove_assigned_team
                          resolve_conversation snooze_conversation change_priority
                          send_email_transcript send_attachment add_private_note].freeze

CONVERSATION_ACTIONS.each do |action_name|
  define_method(action_name) do |pipeline_item, params|
    delegate_to_conversation(pipeline_item, action_name, params)
  end
end

def delegate_to_conversation(pipeline_item, action_name, params)
  conversation = pipeline_item.conversation
  return log_no_conversation(pipeline_item, action_name) if conversation.blank?

  Macros::ExecutionService.new(@macro, conversation, @user).send(action_name, params)
end

def log_no_conversation(pipeline_item, action_name)
  Rails.logger.info(
    "[Macros::PipelineExecutionService] #{action_name}: pipeline_item##{pipeline_item.id} has no linked conversation, skipping"
  )
end
```

Se preferir métodos explícitos em vez do loop com `define_method` (mais alinhado ao estilo
predominante do resto do arquivo, que não usa metaprogramação) — tudo bem, é decisão de
implementação; o importante é que cada um dos 15 nomes acabe delegando para
`Macros::ExecutionService#send(action_name, params)` via `delegate_to_conversation`, sem
reimplementar a lógica de cada ação.

**Por que 15 ações e não as 16 de `CONVERSATION_ACTIONS_ATTRS`**: `send_webhook_event` fica de
fora aqui de propósito — a task 23 já registra `send_webhook_event` em
`Macro::PIPELINE_ACTIONS_ATTRS` apontando para o webhook **nativo do card** (dados do
`pipeline_item`, via `send_pipeline_webhook_event`). Um método `send_webhook_event` não pode
significar duas coisas diferentes na mesma classe — manter o nome reservado para o webhook de
pipeline (é isso que o usuário pediu: "um macro que quando executado, gere um webhook" referindo-se
ao card). Se no futuro for pedido um webhook com dados da conversa vinculada a partir de um
macro de pipeline, precisa de um nome de ação diferente (ex. `send_conversation_webhook_event`)
— fora do escopo desta task.

## Whitelist

`app/models/macro.rb::PIPELINE_ACTIONS_ATTRS` (linha 43-45) — adicionar as 15 ações:
```ruby
PIPELINE_ACTIONS_ATTRS = %w[move_pipeline_item_stage assign_pipeline_item_agent assign_pipeline_item_team
                            add_pipeline_item_label remove_pipeline_item_label update_pipeline_item
                            export_pipeline_item send_webhook_event
                            send_message add_label assign_team assign_agent mute_conversation change_status
                            remove_label remove_assigned_agent remove_assigned_team resolve_conversation
                            snooze_conversation change_priority send_email_transcript send_attachment
                            add_private_note].freeze
```
(`send_webhook_event` já entra aqui pela task 23 — incluído na lista acima por completude.)

## Risco: card sem conversa vinculada

`conversation_id` é opcional em `PipelineItem`. Toda ação nova precisa lidar com esse caso sem
levantar erro — `delegate_to_conversation` já cobre isso (log + `return`, mesmo padrão de
`log_no_pipeline_item` em `AutomationRules::ActionService`). O `rescue StandardError` por-ação já
existente em `Macros::PipelineExecutionService#perform` (linha 22-26) continua sendo a rede de
segurança para qualquer outro erro inesperado.

## Testes

`spec/services/macros/pipeline_execution_service_spec.rb` (existente) — estender com:
- Cada ação de conversa aplicando a mudança esperada quando o card tem `conversation_id`.
- No-op com log quando o card não tem conversa vinculada (não deve levantar erro nem abortar as
  demais ações do macro).

## Critério de pronto

- Macro de pipeline consegue executar as 15 ações de conversa sobre a conversa vinculada ao
  card, sem duplicar a lógica já existente em `Macros::ExecutionService`.
- Card sem conversa vinculada não quebra a execução do macro.
- `bundle exec rubocop -a` limpo.
