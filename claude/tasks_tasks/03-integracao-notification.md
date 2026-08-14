# Task 03 — Backend: integração com `Notification`/`NotificationSetting`

Parte do Grupo A ([visão geral](00-visao-geral.md)). Depende da [01](01-schema-model-task.md).

## Objetivo

Preparar o model `Notification` para aceitar `Task` como `primary_actor` e ganhar um tipo novo
`task_due`. Esta task só mexe em `Notification`/`Task` — quem efetivamente cria a notificação
quando a tarefa vence é a task 04 (job periódico).

## 1. Novo tipo em `NOTIFICATION_TYPES`

`app/models/notification.rb:38-47` — adicionar ao final do hash (nunca reordenar/renumerar as
chaves existentes, o `enum` é armazenado como integer):

```ruby
NOTIFICATION_TYPES = {
  conversation_creation: 1,
  conversation_assignment: 2,
  assigned_conversation_new_message: 3,
  conversation_mention: 4,
  participating_conversation_new_message: 5,
  sla_missed_first_response: 6,
  sla_missed_next_response: 7,
  sla_missed_resolution: 8,
  task_due: 9
}.freeze
```

## 2. `PRIMARY_ACTORS`

`app/models/notification.rb:56`:
```ruby
PRIMARY_ACTORS = %w[Conversation Task].freeze
```
Confirmar onde `PRIMARY_ACTORS` é consumido (`notifications_controller.rb`, ação `read_all`) e
garantir que passar `primary_actor_type: 'Task'` nesse endpoint não quebra — hoje só
`Conversation` é aceito, então esse array precisa desse `'Task'` adicionado.

## 3. `has_many :notifications` em `Task`

`app/models/task.rb` (criado na task 01) — adicionar:
```ruby
has_many :notifications, as: :primary_actor, dependent: :destroy_async
```
Mirror de `Conversation` (`app/models/conversation.rb:113`).

## 4. `push_message_title`/`push_message_body`

`app/models/notification.rb:89-126` — os dois métodos fazem `case`/hash lookup por
`notification_type`. Adicionar branch `task_due` em ambos:

```ruby
# no hash de push_message_title (linha ~90-99):
'task_due' => 'notifications.notification_title.task_due',
```
```ruby
# no if/elsif de push_message_title (linha ~104-111), no ramo "else" (usa primary_actor.display_id) —
# Task não tem display_id como Conversation. Adicionar branch dedicado:
elsif notification_type == 'task_due'
  I18n.t(i18n_key, task_title: primary_actor.title)
```
```ruby
# em push_message_body (case, linha ~116-125):
when 'task_due'
  I18n.t('notifications.task_due_body', due_date: I18n.l(primary_actor.due_date, format: :short))
```

`config/locales/en.yml`, seção `notifications.notification_title.*` (ler o arquivo antes para
achar a seção exata e reaproveitar o estilo das chaves de SLA já existentes):
```yaml
notifications:
  notification_title:
    task_due: 'Task "%{task_title}" is due'
  task_due_body: 'Due %{due_date}'
```

## 5. `NotificationSetting` — nada a fazer

Confirmar (não mudar): `EMAIL_NOTIFICATION_FLAGS`/`PUSH_NOTIFICATION_FLAGS`
(`app/models/notification_setting.rb:30-31`) são gerados dinamicamente a partir de
`Notification::NOTIFICATION_TYPES` — assim que o passo 1 desta task entrar, `email_task_due?`/
`push_task_due?` já existem automaticamente, sem migração. **Não** adicionar `task_due` aos
defaults de `AccountUser#create_notification_setting` (`app/models/account_user.rb:47-48`) —
decisão já registrada na visão geral (fica desligado até o usuário optar, igual aos outros 7
tipos).

## Testes

Só se pedirem. Quando pedido: `Notification.create!(notification_type: 'task_due',
primary_actor: task, ...)` válido; `push_message_title`/`push_message_body` retornam string não
vazia para `task_due`.

## Critério de pronto

- `Notification::NOTIFICATION_TYPES[:task_due]` retorna `9` (ou o próximo inteiro livre, se
  outro tipo tiver sido adicionado por outra branch nesse meio-tempo — checar antes de
  implementar).
- `NotificationSetting.new.email_task_due?` responde (`false` por padrão) sem erro.
- `bundle exec rubocop -a` sem novos warnings.
