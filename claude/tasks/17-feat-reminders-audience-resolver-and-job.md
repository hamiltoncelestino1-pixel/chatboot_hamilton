# Task: Sistema de Lembretes — Resolver de Audiência + Job de Disparo (Cron)

## Objetivo

Fazer o lembrete "acontecer": um job periódico que varre `Reminder`s vencidos e ainda não
notificados, descobre quem deve ser avisado (o resolver de audiência) e dispara uma `Notification`
real pra cada um, reaproveitando `NotificationBuilder` (já corrigido na task
`16-feat-reminders-notification-integration.md`).

**Pré-requisitos:** tasks 15 e 16 implementadas.

Ao final desta task o backend já é **funcionalmente completo ponta a ponta** — dá pra criar um
`Reminder` via console, esperar (ou forçar) o job rodar, e ver a notificação real chegar. Bom
checkpoint de QA manual antes de expor a API REST (task 18).

---

## 1. Resolver de audiência — `app/services/reminders/recipients_resolver.rb`

Implementa a regra já validada com o produto: se tem `assignee`, só ele; senão, quem já tem acesso
ao `remindable`; senão, quem criou.

```ruby
class Reminders::RecipientsResolver
  pattr_initialize [:reminder!]

  def resolve
    return [reminder.assignee] if reminder.assignee_id.present?
    return remindable_audience if reminder.remindable.present?
    return reminder.team.members.to_a if reminder.team_id.present?

    [reminder.created_by]
  end

  private

  def remindable_audience
    case reminder.remindable_type
    when 'PipelineItem'
      pipeline_item_audience
    when 'Conversation'
      conversation_audience
    when 'Contact'
      account_wide_agents
    else
      [reminder.created_by]
    end
  end

  def pipeline_item_audience
    reminder.remindable.pipeline.members.presence || [reminder.created_by]
  end

  def conversation_audience
    conversation = reminder.remindable
    if conversation.team_id.present? && conversation.team.members.any?
      return conversation.team.members.to_a
    end

    conversation.inbox.members.presence || [reminder.created_by]
  end

  def account_wide_agents
    reminder.account.users.merge(AccountUser.where(account_id: reminder.account_id))
  end
end
```

Notas de implementação:
- `reminder.remindable.pipeline` reaproveita o `delegate :pipeline, to: :pipeline_stage` já existente
  em `PipelineItem` (task 06/08 do Kanban) — não duplicar essa cadeia.
- `conversation.inbox.members` / `conversation.team.members` reaproveitam `InboxMember`/`TeamMember`
  já existentes no core do Chatwoot — nenhum model novo aqui.
- `account_wide_agents` não tem um critério melhor disponível hoje porque `Contact` não tem controle
  de acesso granular no Chatwoot (qualquer agente vê qualquer contato).
- O chamador (job, seção 2) é responsável por dar `.uniq` no array antes de iterar — o resolver não
  precisa se preocupar com duplicatas entre `assignee` e membros do registro.

---

## 2. Job — `app/jobs/reminders/notify_due_reminders_job.rb`

```ruby
class Reminders::NotifyDueRemindersJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    Reminder.due_for_notification.find_each(batch_size: 100) { |reminder| process(reminder) }
  end

  private

  def process(reminder)
    # Marca ANTES de notificar (mesmo raciocínio at-most-once do resto do projeto,
    # ver Campaign#trigger! / campaign_status): evita duplicar notificação se o job
    # rodar de novo antes do loop de usuários terminar.
    reminder.mark_as_notified!

    Reminders::RecipientsResolver.new(reminder: reminder).resolve.uniq.each do |user|
      NotificationBuilder.new(
        notification_type: 'reminder_due',
        user: user,
        account: reminder.account,
        primary_actor: reminder
      ).perform
    end
  rescue StandardError => e
    Rails.logger.error("[Reminders::NotifyDueRemindersJob] failed for reminder #{reminder.id}: #{e.message}")
  end
end
```

`Reminder.due_for_notification` é o scope já definido na task 15
(`where(notified_at: nil).where(due_at: ..Time.current)`).

**Trade-off aceito:** marcar `notified_at` antes do fan-out evita duplicar notificação em reruns,
ao custo de eventualmente perder o aviso pra 1 usuário específico se o processo morrer no meio do
loop de usuários (raro, e o mesmo padrão "at-most-once" já é usado em `Campaign`/`campaign_status`
neste projeto — ver `app/services/twilio/oneoff_sms_campaign_service.rb`).

---

## 3. Integração no cron — `app/jobs/trigger_scheduled_items_job.rb`

**Não criar entrada nova em `config/schedule.yml`.** Esse job já roda a cada 5 minutos via
`sidekiq-cron` (confirmado em `config/schedule.yml`) e já é o hub central de "acordar registros
baseado em data vencida" — mesmo raciocínio de `Notification::ReopenSnoozedNotificationsJob` e
`Conversations::ReopenSnoozedConversationsJob`, já despachados por esse mesmo job.

```ruby
class TriggerScheduledItemsJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    Campaign.where(campaign_type: :one_off,
                   campaign_status: :active).where(scheduled_at: 3.days.ago..Time.current).all.find_each(batch_size: 100) do |campaign|
      Campaigns::TriggerOneoffCampaignJob.perform_later(campaign)
    end

    Conversations::ReopenSnoozedConversationsJob.perform_later
    Notification::ReopenSnoozedNotificationsJob.perform_later
    Account::ConversationsResolutionSchedulerJob.perform_later
    Channels::Whatsapp::TemplatesSyncSchedulerJob.perform_later

    # Dispara notificações de lembretes vencidos
    Reminders::NotifyDueRemindersJob.perform_later
  end
end

TriggerScheduledItemsJob.prepend_mod_with('TriggerScheduledItemsJob')
```

---

## 4. Specs

### `spec/services/reminders/recipients_resolver_spec.rb`

Um exemplo por ramo de decisão:
1. `assignee` presente → só ele, independente de `remindable`.
2. Sem assignee, `remindable` é `PipelineItem` → todos os `pipeline.members`.
3. Sem assignee, `remindable` é `PipelineItem` sem nenhum membro → fallback pro `created_by`.
4. Sem assignee, `remindable` é `Conversation` com `team_id` → só o time.
5. Sem assignee, `remindable` é `Conversation` sem time → membros da inbox.
6. Sem assignee, `remindable` é `Contact` → todos os agentes/admins da conta.
7. Sem assignee, sem `remindable`, com `team_id` no lembrete → membros do time.
8. Sem assignee, sem `remindable`, sem `team_id` → só `created_by`.

### `spec/jobs/reminders/notify_due_reminders_job_spec.rb`

O teste mais importante: rodar o job **duas vezes seguidas** sobre o mesmo `Reminder` vencido e
confirmar que a segunda rodada **não cria uma segunda `Notification`** (idempotência via
`notified_at`). Cobrir também: reminder ainda não vencido não é processado; reminder já `notified_at`
preenchido é ignorado; erro num reminder não impede o processamento dos demais no mesmo batch (usar
`rescue StandardError` do job).

---

## Verificação

```ruby
# rails console
account = Account.first
pipeline = account.pipelines.first
agent1, agent2 = account.users.first(2)
pipeline.add_members([agent1.id, agent2.id])

reminder = Reminder.create!(
  account: account, title: 'Follow-up', due_at: 1.minute.ago,
  created_by: agent1, remindable: pipeline.pipeline_items.first
)

Reminders::NotifyDueRemindersJob.perform_now

reminder.reload.notified_at.present? # => true
agent1.notifications.where(notification_type: 'reminder_due').exists? # => true
agent2.notifications.where(notification_type: 'reminder_due').exists? # => true

# Rodar de novo — não deve duplicar
count_before = Notification.where(notification_type: 'reminder_due').count
Reminders::NotifyDueRemindersJob.perform_now
Notification.where(notification_type: 'reminder_due').count == count_before # => true
```

1. Rodar `bundle exec rspec spec/services/reminders/ spec/jobs/reminders/` — tudo verde.
2. Confirmar via `Sidekiq::Cron::Job` (ou aguardar 5 minutos em ambiente local com Sidekiq rodando)
   que `TriggerScheduledItemsJob` dispara `Reminders::NotifyDueRemindersJob` automaticamente.
3. Repetir o cenário de verificação pra `Conversation` (com e sem time) e `Contact`.
