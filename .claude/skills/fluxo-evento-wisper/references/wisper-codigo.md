# Código de referência — fluxo de evento Wisper

Todo o código abaixo foi lido verbatim do repositório nesta sessão. Use como referência exata
ao implementar um evento novo — não parafraseie a partir daqui sem checar se o arquivo real
mudou.

## `app/dispatchers/dispatcher.rb` (24 linhas)

```ruby
class Dispatcher
  include Singleton

  attr_reader :async_dispatcher, :sync_dispatcher

  def self.dispatch(event_name, timestamp, data, async = false)
    Rails.configuration.dispatcher.dispatch(event_name, timestamp, data, async)
  end

  def initialize
    @sync_dispatcher = SyncDispatcher.new
    @async_dispatcher = AsyncDispatcher.new
  end

  def dispatch(event_name, timestamp, data, _async = false)
    @sync_dispatcher.dispatch(event_name, timestamp, data)
    @async_dispatcher.dispatch(event_name, timestamp, data)
  end

  def load_listeners
    @sync_dispatcher.load_listeners
    @async_dispatcher.load_listeners
  end
end
```

Note que `dispatch` (linha 15-18) chama **os dois** dispatchers incondicionalmente — o
parâmetro `async` é ignorado (`_async`). Não existe um jeito de disparar "só síncrono" ou "só
assíncrono" via essa API pública.

## `app/dispatchers/base_dispatcher.rb` (11 linhas)

```ruby
class BaseDispatcher
  include Wisper::Publisher

  def listeners
    []
  end

  def load_listeners
    listeners.each { |listener| subscribe(listener) }
  end
end
```

## `app/dispatchers/sync_dispatcher.rb` (10 linhas)

```ruby
class SyncDispatcher < BaseDispatcher
  def dispatch(event_name, timestamp, data)
    event_object = Events::Base.new(event_name, timestamp, data)
    publish(event_object.method_name, event_object)
  end

  def listeners
    [ActionCableListener.instance, AgentBotListener.instance]
  end
end
```

## `app/dispatchers/async_dispatcher.rb` (27 linhas)

```ruby
class AsyncDispatcher < BaseDispatcher
  def dispatch(event_name, timestamp, data)
    EventDispatcherJob.perform_later(event_name, timestamp, data)
  end

  def publish_event(event_name, timestamp, data)
    event_object = Events::Base.new(event_name, timestamp, data)
    publish(event_object.method_name, event_object)
  end

  def listeners
    [
      AutomationRuleListener.instance,
      CampaignListener.instance,
      CsatSurveyListener.instance,
      HookListener.instance,
      InstallationWebhookListener.instance,
      NotificationListener.instance,
      ParticipationListener.instance,
      ReportingEventListener.instance,
      WebhookListener.instance
    ]
  end
end

AsyncDispatcher.prepend_mod_with('AsyncDispatcher')
```

`dispatch` (linha 2-4) não publica direto — enfileira `EventDispatcherJob`, que mais tarde
chama `publish_event` (linha 6-9), onde o Wisper `publish` de fato acontece.

## `app/jobs/event_dispatcher_job.rb` (7 linhas)

```ruby
class EventDispatcherJob < ApplicationJob
  queue_as :critical

  def perform(event_name, timestamp, data)
    Rails.configuration.dispatcher.async_dispatcher.publish_event(event_name, timestamp, data)
  end
end
```

## `config/initializers/event_handlers.rb` (6 linhas)

```ruby
Rails.application.configure do
  config.to_prepare do
    Rails.configuration.dispatcher = Dispatcher.instance
    Rails.configuration.dispatcher.load_listeners
  end
end
```

Roda em `config.to_prepare` (boot + todo reload em dev) — é aqui que os arrays `listeners` de
`SyncDispatcher`/`AsyncDispatcher` são assinados no Wisper. Adicionar um listener ao array já
é suficiente; nada mais precisa ser registrado manualmente.

## `app/listeners/base_listener.rb` (39 linhas)

```ruby
class BaseListener
  include Singleton

  def extract_conversation_and_account(event)
    conversation = event.data[:conversation]
    [conversation, conversation.account]
  end

  def extract_notification_and_account(event)
    notification = event.data[:notification]
    notification_finder = NotificationFinder.new(notification.user, notification.account)
    unread_count = notification_finder.unread_count
    count = notification_finder.count
    [notification, notification.account, unread_count, count]
  end

  def extract_message_and_account(event)
    message = event.data[:message]
    [message, message.account]
  end

  def extract_contact_and_account(event)
    contact = event.data[:contact]
    [contact, contact.account]
  end

  def extract_inbox_and_account(event)
    inbox = event.data[:inbox]
    [inbox, inbox.account]
  end

  def extract_changed_attributes(event)
    changed_attributes = event.data[:changed_attributes]

    return if changed_attributes.blank?

    changed_attributes.map { |k, v| { k => { previous_value: v[0], current_value: v[1] } } }
  end
end
```

Helpers de extração já existentes — reaproveite em vez de escrever `event.data[:x]` toda vez,
se o seu evento carrega um dos tipos já cobertos (conversation, notification, message,
contact, inbox). Se seu evento carrega outro tipo de dado (ex. `pipeline_item`), acesse
`event.data[:pipeline_item]` diretamente, como faz `ActionCableListener#pipeline_item_created`.

## `app/listeners/automation_rule_listener.rb` — trechos relevantes

Mapeamento evento → método (Wisper resolve pelo nome, `.`→`_`):

```ruby
def conversation_updated(event)
  process_conversation_event(event, 'conversation_updated')
end

def conversation_created(event)
  process_conversation_event(event, 'conversation_created')
end

def pipeline_item_stage_changed(event)
  process_pipeline_item_event(event, 'pipeline_item_stage_changed')
end
```

Guard de loop (linhas 97-99):

```ruby
def performed_by_automation?(event)
  event.data[:performed_by].present? && event.data[:performed_by].instance_of?(AutomationRule)
end
```

Usado como early-return no topo dos processadores:

```ruby
def process_pipeline_item_event(event, event_name)
  return if performed_by_automation?(event)
  # ...
end

def process_conversation_event(event, event_name)
  return if performed_by_automation?(event)
  # ...
end
```

Busca de regras ativas pelo nome do evento (linhas 89-95):

```ruby
def current_account_rules(event_name, account)
  AutomationRule.where(
    event_name: event_name,
    account_id: account.id,
    active: true
  )
end
```

## `app/listeners/action_cable_listener.rb` — os 3 padrões de token + broadcast

**Conta inteira** (account-wide), ex. `contact_created` (linhas 146-149) e o par
`pipeline_item_created`/`pipeline_item_updated` (linhas 176-188):

```ruby
def contact_created(event)
  contact, account = extract_contact_and_account(event)
  broadcast(account, [account_token(account)], CONTACT_CREATED, contact.push_event_data)
end

def pipeline_item_created(event)
  pipeline_item = event.data[:pipeline_item]
  account = pipeline_item.account

  broadcast(account, [account_token(account)], PIPELINE_ITEM_CREATED, pipeline_item.push_event_data)
end

def pipeline_item_updated(event)
  pipeline_item = event.data[:pipeline_item]
  account = pipeline_item.account

  broadcast(account, [account_token(account)], PIPELINE_ITEM_UPDATED, pipeline_item.push_event_data)
end
```

**Agentes+admins de um inbox + contato**, `message_created` (linhas 41-47):

```ruby
def message_created(event)
  message, account = extract_message_and_account(event)
  conversation = message.conversation
  tokens = user_tokens(account, conversation.inbox.members) + contact_tokens(conversation.contact_inbox, message)

  broadcast(account, tokens, MESSAGE_CREATED, message.push_event_data)
end
```

**Token de usuário específico** (não usa um helper de escopo, pega direto), `notification_created`
(linhas 4-8):

```ruby
def notification_created(event)
  notification, account, unread_count, count = extract_notification_and_account(event)
  tokens = [event.data[:notification].user.pubsub_token]
  broadcast(account, tokens, NOTIFICATION_CREATED, { notification: notification.push_event_data, unread_count: unread_count, count: count })
end
```

Métodos privados de escopo de token (linhas 190-236):

```ruby
private

def account_token(account)
  "account_#{account.id}"
end

def typing_event_listener_tokens(account, conversation, user)
  current_user_token = if user.is_a?(Contact)
                         conversation.contact_inbox.pubsub_token
                       elsif user.respond_to?(:pubsub_token)
                         user.pubsub_token
                       end

  tokens = user_tokens(account, conversation.inbox.members) + [conversation.contact_inbox.pubsub_token]
  current_user_token.present? ? tokens - [current_user_token] : tokens
end

def user_tokens(account, agents)
  agent_tokens = agents.pluck(:pubsub_token)
  admin_tokens = account.administrators.pluck(:pubsub_token)
  (agent_tokens + admin_tokens).uniq
end

def contact_tokens(contact_inbox, message)
  return [] if message.private?
  return [] if message.activity?
  return [] if contact_inbox.nil?

  contact_inbox_tokens(contact_inbox)
end

def contact_inbox_tokens(contact_inbox)
  contact = contact_inbox.contact

  contact_inbox.hmac_verified? ? contact.contact_inboxes.where(hmac_verified: true).filter_map(&:pubsub_token) : [contact_inbox.pubsub_token]
end

def broadcast(account, tokens, event_name, data)
  return if tokens.blank?

  payload = data.merge(account_id: account.id)
  # So the frondend knows who performed the action.
  # Useful in cases like conversation assignment for generating a notification with assigner name.
  payload[:performer] = Current.user&.push_event_data if Current.user.present?

  ::ActionCableBroadcastJob.perform_later(tokens.uniq, event_name, payload)
end
```

(final do arquivo: `ActionCableListener.prepend_mod_with('ActionCableListener')` — ver skill
`sincronizar-enterprise` se for mexer nesse listener, pois pode ter mod em `enterprise/`.)

## `app/jobs/action_cable_broadcast_job.rb` (44 linhas)

```ruby
class ActionCableBroadcastJob < ApplicationJob
  queue_as :critical
  include Events::Types

  CONVERSATION_UPDATE_EVENTS = [
    CONVERSATION_READ,
    CONVERSATION_UPDATED,
    TEAM_CHANGED,
    ASSIGNEE_CHANGED,
    CONVERSATION_STATUS_CHANGED
  ].freeze

  def perform(members, event_name, data)
    return if members.blank?

    broadcast_data = prepare_broadcast_data(event_name, data)
    broadcast_to_members(members, event_name, broadcast_data)
  end

  private

  # Ensures that only the latest available data is sent to prevent UI issues
  # caused by out-of-order events during high-traffic periods. This prevents
  # the conversation job from processing outdated data.
  def prepare_broadcast_data(event_name, data)
    return data unless CONVERSATION_UPDATE_EVENTS.include?(event_name)

    account = Account.find(data[:account_id])
    conversation = account.conversations.find_by!(display_id: data[:id])
    conversation.push_event_data.merge(account_id: data[:account_id])
  end

  def broadcast_to_members(members, event_name, broadcast_data)
    members.each do |member|
      ActionCable.server.broadcast(
        member,
        {
          event: event_name,
          data: broadcast_data
        }
      )
    end
  end
end
```

Se o seu evento novo for um "conversation update" (muda algo que a UI de conversa mostra),
considere se ele precisa entrar em `CONVERSATION_UPDATE_EVENTS` para reduzir risco de payload
desatualizado em cenários de alto tráfego.

## `app/channels/room_channel.rb` (59 linhas)

```ruby
class RoomChannel < ApplicationCable::Channel
  def subscribed
    current_user
    current_account
    ensure_stream
    update_subscription
    broadcast_presence
  end

  def update_presence
    update_subscription
    broadcast_presence
  end

  private

  def broadcast_presence
    return if @current_account.blank?

    data = { account_id: @current_account.id, users: ::OnlineStatusTracker.get_available_users(@current_account.id) }
    data[:contacts] = ::OnlineStatusTracker.get_available_contacts(@current_account.id) if @current_user.is_a? User
    ActionCable.server.broadcast(pubsub_token, { event: 'presence.update', data: data })
  end

  def ensure_stream
    stream_from pubsub_token
    stream_from "account_#{@current_account.id}" if @current_account.present? && @current_user.is_a?(User)
  end

  def update_subscription
    return if @current_account.blank?

    ::OnlineStatusTracker.update_presence(@current_account.id, @current_user.class.name, @current_user.id)
  end

  def pubsub_token
    @pubsub_token ||= params[:pubsub_token]
  end

  def current_user
    @current_user ||= if params[:user_id].blank?
                        ContactInbox.find_by!(pubsub_token: pubsub_token).contact
                      else
                        User.find_by!(pubsub_token: pubsub_token, id: params[:user_id])
                      end
  end

  def current_account
    return if current_user.blank?

    @current_account ||= if @current_user.is_a? Contact
                           @current_user.account
                         else
                           @current_user.accounts.find(params[:account_id])
                         end
  end
end
```

`ensure_stream` (linhas 27-30) é o porquê de broadcasts `account_#{id}` chegarem em todo mundo:
todo `User` logado assina automaticamente esse stream, além do seu próprio `pubsub_token`.

## `lib/events/types.rb` (71 linhas, completo)

```ruby
# frozen_string_literal: true

module Events::Types
  ### Installation Events ###
  # account events
  ACCOUNT_CREATED = 'account.created'
  ACCOUNT_CACHE_INVALIDATED = 'account.cache_invalidated'

  #### Account Events ###
  # campaign events
  CAMPAIGN_TRIGGERED = 'campaign.triggered'

  # channel events
  WEBWIDGET_TRIGGERED = 'webwidget.triggered'

  # conversation events
  CONVERSATION_CREATED = 'conversation.created'
  CONVERSATION_UPDATED = 'conversation.updated'
  CONVERSATION_READ = 'conversation.read'
  CONVERSATION_BOT_HANDOFF = 'conversation.bot_handoff'
  # FIXME: deprecate the opened and resolved events in future in favor of status changed event.
  CONVERSATION_OPENED = 'conversation.opened'
  CONVERSATION_RESOLVED = 'conversation.resolved'
  CONVERSATION_CAPTAIN_INFERENCE_RESOLVED = 'conversation.captain_inference_resolved'
  CONVERSATION_CAPTAIN_INFERENCE_HANDOFF = 'conversation.captain_inference_handoff'

  CONVERSATION_STATUS_CHANGED = 'conversation.status_changed'
  CONVERSATION_CONTACT_CHANGED = 'conversation.contact_changed'
  ASSIGNEE_CHANGED = 'assignee.changed'
  TEAM_CHANGED = 'team.changed'
  CONVERSATION_TYPING_ON = 'conversation.typing_on'
  CONVERSATION_TYPING_OFF = 'conversation.typing_off'
  CONVERSATION_MENTIONED = 'conversation.mentioned'

  # message events
  MESSAGE_CREATED = 'message.created'
  FIRST_REPLY_CREATED = 'first.reply.created'
  REPLY_CREATED = 'reply.created'
  MESSAGE_UPDATED = 'message.updated'

  # contact events
  CONTACT_CREATED = 'contact.created'
  CONTACT_UPDATED = 'contact.updated'
  CONTACT_MERGED = 'contact.merged'
  CONTACT_DELETED = 'contact.deleted'

  # contact events
  INBOX_CREATED = 'inbox.created'
  INBOX_UPDATED = 'inbox.updated'

  # notification events
  NOTIFICATION_CREATED = 'notification.created'
  NOTIFICATION_DELETED = 'notification.deleted'
  NOTIFICATION_UPDATED = 'notification.updated'

  # agent events
  AGENT_ADDED = 'agent.added'
  AGENT_REMOVED = 'agent.removed'

  # copilot events
  COPILOT_MESSAGE_CREATED = 'copilot.message.created'

  # pipeline item events
  PIPELINE_ITEM_CREATED = 'pipeline_item.created'
  PIPELINE_ITEM_STAGE_CHANGED = 'pipeline_item.stage_changed'
  # Broader than PIPELINE_ITEM_STAGE_CHANGED on purpose: used only for the Kanban real-time
  # broadcast (task 10), not automation rules (task 09 deliberately only reacts to stage
  # changes). Fires on stage/assignee/team change - the fields that affect a card's
  # position/appearance on the board.
  PIPELINE_ITEM_UPDATED = 'pipeline_item.updated'
end
```

## `app/javascript/dashboard/helper/actionCable.js` — mapa `events` (linhas 15-40)

```js
this.events = {
  'message.created': this.onMessageCreated,
  'message.updated': this.onMessageUpdated,
  'conversation.created': this.onConversationCreated,
  'conversation.status_changed': this.onStatusChange,
  'user:logout': this.onLogout,
  'page:reload': this.onReload,
  'assignee.changed': this.onAssigneeChanged,
  'conversation.typing_on': this.onTypingOn,
  'conversation.typing_off': this.onTypingOff,
  'conversation.contact_changed': this.onConversationContactChange,
  'presence.update': this.onPresenceUpdate,
  'contact.deleted': this.onContactDelete,
  'contact.updated': this.onContactUpdate,
  'conversation.mentioned': this.onConversationMentioned,
  'notification.created': this.onNotificationCreated,
  'notification.deleted': this.onNotificationDeleted,
  'notification.updated': this.onNotificationUpdated,
  'conversation.read': this.onConversationRead,
  'conversation.updated': this.onConversationUpdated,
  'account.cache_invalidated': this.onCacheInvalidate,
  'account.enrichment_completed': this.onEnrichmentCompleted,
  'copilot.message.created': this.onCopilotMessageCreated,
  'pipeline_item.created': this.onPipelineItemChanged,
  'pipeline_item.updated': this.onPipelineItemChanged,
};
```

Handler de exemplo (linhas 204-206, um handler compartilhado por dois eventos):

```js
onPipelineItemChanged = data => {
  this.app.$store.dispatch('kanban/applyRealtimePipelineItem', data);
};
```

Outro exemplo com lógica extra além do dispatch (linhas 87-90):

```js
onConversationCreated = data => {
  this.app.$store.dispatch('addConversation', data);
  this.fetchConversationStats();
};
```

## Exemplo ponta a ponta — `app/models/pipeline_item.rb`

Callbacks (linhas 63-65):

```ruby
after_create :dispatch_created_event
after_update :dispatch_stage_changed_event, if: :saved_change_to_pipeline_stage_id?
after_update :dispatch_updated_event, if: :broadcast_relevant_change?
```

Métodos de dispatch (linhas 105-131):

```ruby
def dispatch_created_event
  Rails.configuration.dispatcher.dispatch(
    Events::Types::PIPELINE_ITEM_CREATED, Time.zone.now,
    pipeline_item: self, performed_by: Current.executed_by
  )
end

def dispatch_stage_changed_event
  Rails.configuration.dispatcher.dispatch(
    Events::Types::PIPELINE_ITEM_STAGE_CHANGED, Time.zone.now,
    pipeline_item: self, performed_by: Current.executed_by,
    previous_stage_id: saved_change_to_pipeline_stage_id.first
  )
end

# Broader than saved_change_to_pipeline_stage_id? on purpose - see PIPELINE_ITEM_UPDATED's
# comment in lib/events/types.rb.
def broadcast_relevant_change?
  saved_change_to_pipeline_stage_id? || saved_change_to_assignee_id? || saved_change_to_team_id?
end

def dispatch_updated_event
  Rails.configuration.dispatcher.dispatch(
    Events::Types::PIPELINE_ITEM_UPDATED, Time.zone.now,
    pipeline_item: self, performed_by: Current.executed_by
  )
end
```

`push_event_data` — o payload que de fato vai pro frontend via ActionCable (linhas 69-89):

```ruby
def push_event_data
  {
    id: id,
    title: title,
    value: value,
    notes: notes,
    position: position,
    pipeline_stage_id: pipeline_stage_id,
    pipeline_id: pipeline_stage.pipeline_id,
    pipeline_name: pipeline_stage.pipeline.name,
    pipeline_stage_name: pipeline_stage.name,
    conversation_id: conversation_id,
    created_at: created_at.to_i,
    updated_at: updated_at.to_i,
    contact: contact_push_event_data,
    assignee: assignee&.push_event_data,
    team: team&.push_event_data,
    label_list: label_list,
    custom_attributes: custom_attributes
  }
end
```
