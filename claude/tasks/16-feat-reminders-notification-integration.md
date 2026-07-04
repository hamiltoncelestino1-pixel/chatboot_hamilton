# Task: Sistema de Lembretes — Integração com Notification

## Objetivo

Fazer o `Reminder` (criado na task `15-feat-reminders-backend-foundation.md`) virar um
`notification_type` de verdade dentro do sistema de `Notification` já existente — reaproveitando
100% da entrega (sino/badge, tempo real via ActionCable, push, email) sem duplicar infraestrutura.

**Pré-requisito:** task 15 implementada (`Reminder` existe).

---

## 1. Achado crítico — corrigir `NotificationBuilder` ANTES de tudo

`app/builders/notification_builder.rb#build_notification` (lido integralmente) tem uma guarda
**hardcoded para Conversation**:

```ruby
def build_notification
  return if notification_type == 'conversation_creation' && !user_subscribed_to_notification?
  return if primary_actor.contact.blocked? && notification_type != 'conversation_mention'
  # ...
end
```

`primary_actor.contact` assume que todo `primary_actor` responde a `.contact` — verdade pra
`Conversation`, **falso pra `Reminder`**. Sem essa correção, toda tentativa de criar uma
`Notification` com `primary_actor: reminder` vai estourar `NoMethodError: undefined method
'contact' for #<Reminder>`.

**Correção obrigatória:**

```ruby
def build_notification
  return if notification_type == 'conversation_creation' && !user_subscribed_to_notification?
  return if primary_actor.respond_to?(:contact) && primary_actor.contact&.blocked? && notification_type != 'conversation_mention'

  user.notifications.create!(
    notification_type: notification_type,
    account: account,
    primary_actor: primary_actor,
    secondary_actor: secondary_actor || current_user
  )
end
```

Rodar a suíte existente de `spec/builders/notification_builder_spec.rb` (se existir) após a mudança
para confirmar que nenhum `notification_type` existente quebrou.

---

## 2. `app/models/notification.rb`

### `NOTIFICATION_TYPES`

Hoje vai de 1 a 8 (`conversation_creation` até `sla_missed_resolution`). Acrescentar **no final do
hash**, nunca reordenar os existentes:

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
  reminder_due: 9
}.freeze
```

**Por quê a ordem importa:** `NotificationSetting` (próxima seção) usa a gem `FlagShihTzu`, que
deriva a posição do bit de cada flag a partir da ordem deste hash. Reordenar os existentes quebraria
os bitmasks (`email_flags`/`push_flags`) já salvos em produção — sempre **acrescentar no final**.

### `push_message_title`

```ruby
def push_message_title
  notification_title_map = {
    'conversation_creation' => 'notifications.notification_title.conversation_creation',
    'conversation_assignment' => 'notifications.notification_title.conversation_assignment',
    'assigned_conversation_new_message' => 'notifications.notification_title.assigned_conversation_new_message',
    'participating_conversation_new_message' => 'notifications.notification_title.assigned_conversation_new_message',
    'conversation_mention' => 'notifications.notification_title.conversation_mention',
    'sla_missed_first_response' => 'notifications.notification_title.sla_missed_first_response',
    'sla_missed_next_response' => 'notifications.notification_title.sla_missed_next_response',
    'sla_missed_resolution' => 'notifications.notification_title.sla_missed_resolution',
    'reminder_due' => 'notifications.notification_title.reminder_due'
  }

  i18n_key = notification_title_map[notification_type]
  return '' unless i18n_key

  if notification_type == 'conversation_creation'
    I18n.t(i18n_key, display_id: conversation.display_id, inbox_name: primary_actor.inbox.name)
  elsif %w[conversation_assignment assigned_conversation_new_message participating_conversation_new_message
           conversation_mention].include?(notification_type)
    I18n.t(i18n_key, display_id: conversation.display_id)
  elsif notification_type == 'reminder_due'
    I18n.t(i18n_key, title: primary_actor.title)
  else
    I18n.t(i18n_key, display_id: primary_actor.display_id)
  end
end
```

### `push_message_body`

```ruby
def push_message_body
  case notification_type
  when 'conversation_creation', 'sla_missed_first_response'
    message_body(conversation.messages.first)
  when 'assigned_conversation_new_message', 'participating_conversation_new_message', 'conversation_mention'
    message_body(secondary_actor)
  when 'conversation_assignment', 'sla_missed_next_response', 'sla_missed_resolution'
    message_body((conversation.messages.incoming.last || conversation.messages.outgoing.last))
  when 'reminder_due'
    primary_actor.description.presence || I18n.t('notifications.reminder_due_body', title: primary_actor.title)
  else
    ''
  end
end
```

### `PRIMARY_ACTORS`

Opcional (não bloqueante): `PRIMARY_ACTORS = ['Conversation'].freeze` é usado só pelo filtro de
`read_all` (marcar como lidas todas notificações de um `primary_actor` específico). Adicionar
`'Reminder'` (`PRIMARY_ACTORS = ['Conversation', 'Reminder'].freeze`) se quiser suportar "marcar
como lidas todas as notificações desse lembrete" a partir da UI — não crítico pro MVP, pode ficar
pra depois.

---

## 3. `app/models/notification_setting.rb` — nenhuma migração necessária

Confirmado por leitura direta: essa tabela **não tem uma coluna por tipo de notificação**. São só
2 colunas bitmask (`email_flags`, `push_flags`, ambas `integer`), e a gem `FlagShihTzu` gera os
métodos `email_<tipo>?`/`push_<tipo>?` automaticamente a partir de `Notification::NOTIFICATION_TYPES`.
Assim que o passo 2 acima for aplicado, `email_reminder_due?`/`push_reminder_due?` passam a existir
sozinhos — **nenhuma migração ou edição de código extra necessária neste model**.

---

## 4. `app/models/account_user.rb` — flags default

```ruby
def create_notification_setting
  setting = user.notification_settings.new(account_id: account.id)
  setting.selected_email_flags = [:email_conversation_assignment, :email_reminder_due]
  setting.selected_push_flags = [:push_conversation_assignment, :push_reminder_due]
  setting.save!
end
```

**Decisão de produto assumida**: `reminder_due` vem **ligado por padrão** pra email e push (ao
contrário de `conversation_creation`, que é opt-in porque é ruidoso por natureza) — um lembrete só
existe porque alguém pediu deliberadamente pra ser avisado. Confirmar essa decisão antes de
implementar se preferir o padrão oposto (opt-in).

Nota: isso só afeta contas/usuários **novos** a partir de agora — usuários já existentes não
recebem esse flag retroativamente (`FlagShihTzu` é bit-based, então simplesmente lê como "desligado"
até o usuário ativar manualmente em Perfil > Notificações). Se quiser ativar retroativamente pra
todo mundo, seria necessário um script/migração de dados à parte — fora do escopo desta task.

---

## 5. Mailer — `app/mailers/agent_notifications/conversation_notifications_mailer.rb`

Confirmado por leitura de `app/services/notification/email_notification_service.rb`:
```ruby
AgentNotifications::ConversationNotificationsMailer.with(account: notification.account).public_send(
  notification.notification_type.to_s, notification.primary_actor, notification.user, notification.secondary_actor
).deliver_later
```
O nome do método precisa ser exatamente igual ao `notification_type` (`'reminder_due'` →
`#reminder_due`), independente do nome "Conversation" no mailer.

```ruby
def reminder_due(reminder, agent, _user)
  return unless smtp_config_set_or_development?

  @agent = agent
  @reminder = reminder
  subject = "#{@agent.available_name}, you have a reminder due: #{@reminder.title}"
  @action_url = reminder_action_url(@reminder)
  send_mail_with_liquid(to: @agent.email, subject: subject) and return
end

private

def reminder_action_url(reminder)
  case reminder.remindable_type
  when 'Conversation'
    app_account_conversation_url(account_id: reminder.account_id, id: reminder.remindable.display_id)
  when 'Contact'
    "#{ENV.fetch('FRONTEND_URL', nil)}/app/accounts/#{reminder.account_id}/contacts/#{reminder.remindable_id}"
  when 'PipelineItem'
    "#{ENV.fetch('FRONTEND_URL', nil)}/app/accounts/#{reminder.account_id}/kanban"
  else
    "#{ENV.fetch('FRONTEND_URL', nil)}/app/accounts/#{reminder.account_id}/reminders"
  end
end
```

`liquid_droppables` (método privado existente que monta o contexto do template) ganha `reminder:
@reminder` no merge.

### Template — `app/views/mailers/agent_notifications/conversation_notifications_mailer/reminder_due.liquid`

Seguir a estrutura mínima de `conversation_assignment.liquid` (mesmo mailer, já existente): saudação
com `{{user.available_name}}`, título e data de vencimento do lembrete, CTA `<a href="{{action_url}}">`.

---

## 6. i18n backend — `config/locales/en.yml` (e demais locales)

```yaml
en:
  notifications:
    notification_title:
      reminder_due: 'Reminder due: %{title}'
    reminder_due_body: 'Reminder: %{title}'
```

---

## Verificação

```ruby
# rails console
account = Account.first
agent = account.users.first
reminder = Reminder.create!(account: account, title: 'Ligar pro cliente', due_at: 1.hour.ago, created_by: agent)

NotificationBuilder.new(
  notification_type: 'reminder_due', user: agent, account: account, primary_actor: reminder
).perform
# não deve estourar erro (confirma a correção do NotificationBuilder)

notification = agent.notifications.last
notification.push_message_title # => "Reminder due: Ligar pro cliente"
notification.push_message_body  # => "Reminder: Ligar pro cliente"
```

1. Rodar a suíte de specs de `notification.rb`/`notification_builder.rb`/`notification_setting.rb`
   já existentes — confirmar que **nenhum notification_type antigo quebrou** com as mudanças.
2. Confirmar em Perfil > Notificações (UI) que aparecem novas opções pra "Lembrete vencido" (email/push)
   pra um usuário **novo** criado após essa mudança.
3. Confirmar que o email é enviado (checar log/letter_opener em dev) ao chamar `NotificationBuilder`
   manualmente como acima com um usuário cujo `notification_setting` tenha `email_reminder_due` ligado.
