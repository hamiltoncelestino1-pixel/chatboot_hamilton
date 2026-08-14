# Task 05 — Backend: eventos Wisper + broadcast ActionCable de tarefas

Parte do Grupo A ([visão geral](00-visao-geral.md)). Depende da [01](01-schema-model-task.md).

## Objetivo

Fazer os 4 eventos que `Task` já dispara (task 01: `TASK_CREATED/UPDATED/COMPLETED/DELETED`)
chegarem em tempo real nos 3 pontos de entrada (card de pipeline aberto por outro agente,
sidebar de conversa, perfil do contato). Copia 1:1 o padrão de `PipelineItem`
(`pipeline_item_created`/`pipeline_item_updated` em `app/listeners/action_cable_listener.rb:176-188`),
que já broadcasta account-wide (`account_#{id}`) em vez de só para membros de um inbox
específico — igual se aplica aqui, já que uma tarefa pode não ter conversa nem inbox associado.

## 1. Tipos de evento — `lib/events/types.rb`

Adicionar seção nova, ao lado da de pipeline item (linha ~63-70):

```ruby
# task events
TASK_CREATED = 'task.created'
TASK_UPDATED = 'task.updated'
TASK_COMPLETED = 'task.completed'
TASK_DELETED = 'task.deleted'
```
(Se a task 01 já tiver sido implementada com essas constantes como stub, só confirmar que
batem exatamente com o que o model usa.)

## 2. `ActionCableListener`

`app/listeners/action_cable_listener.rb` — adicionar ao lado dos handlers de
`pipeline_item_*` (linha ~176-188):

```ruby
def task_created(event)
  task = event.data[:task]
  account = task.account

  broadcast(account, [account_token(account)], TASK_CREATED, task.push_event_data)
end

def task_updated(event)
  task = event.data[:task]
  account = task.account

  broadcast(account, [account_token(account)], TASK_UPDATED, task.push_event_data)
end

def task_completed(event)
  task = event.data[:task]
  account = task.account

  broadcast(account, [account_token(account)], TASK_COMPLETED, task.push_event_data)
end

def task_deleted(event)
  task_data = event.data[:task_data]
  account = Account.find_by(id: task_data[:account_id])
  return if account.blank?

  broadcast(account, [account_token(account)], TASK_DELETED, { task: { id: task_data[:id] } })
end
```

`account_token` já existe como helper privado (`action_cable_listener.rb:192-194`), não
precisa duplicar.

## 3. `RoomChannel` — nenhuma mudança necessária

`app/channels/room_channel.rb` já faz `stream_from "account_#{id}"` para usuários logados —
confirmar isso lendo o arquivo, mas não deve precisar de mudança (mesmo canal que
`pipeline_item.*` já usa).

## Testes

Só se pedirem. Quando pedido: `spec/listeners/action_cable_listener_spec.rb` já tem exemplos
para `pipeline_item_created`/`pipeline_item_updated` — mirror para os 4 casos de `task_*`.

## Critério de pronto

- Disparar `Rails.configuration.dispatcher.dispatch(Events::Types::TASK_CREATED, ...)`
  manualmente no console e confirmar (via log ou teste) que `ActionCableBroadcastJob` é
  enfileirado com o token `account_#{id}` certo.
- `bundle exec rubocop -a` sem novos warnings.
