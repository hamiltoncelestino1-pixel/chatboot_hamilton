# Task 04 — Backend: job periódico de vencimento + disparo de notificação

Parte do Grupo A ([visão geral](00-visao-geral.md)). Depende da [01](01-schema-model-task.md) e
[03](03-integracao-notification.md).

## Objetivo

Toda tarefa com `due_date` vencido, ainda não notificada (`reminder_sent_at: nil`) e não
concluída (`completed_at: nil`), dispara uma notificação `task_due` para o `assignee`. Copia o
padrão exato de `TriggerScheduledItemsJob` + o precedente de `SlaEvent#create_notifications`
(`enterprise/app/models/sla_event.rb:64-86`) — chamar `NotificationBuilder` direto, sem Wisper.

## 1. Job orquestrador — `app/jobs/tasks/trigger_due_tasks_job.rb`

```ruby
module Tasks
  class TriggerDueTasksJob < ApplicationJob
    queue_as :scheduled_jobs

    def perform
      Task.where(reminder_sent_at: nil, completed_at: nil)
          .where(due_date: 3.days.ago..Time.current)
          .find_each(batch_size: 100) do |task|
        Tasks::NotifyDueTaskJob.perform_later(task)
      end
    end
  end
end
```

Mesma forma de `Campaign.where(...).find_each { |c| Campaigns::TriggerOneoffCampaignJob.perform_later(c) }`
em `app/jobs/trigger_scheduled_items_job.rb:6-9`. Janela de 3 dias é a mesma convenção usada em
todo o projeto (ver risco #3 da visão geral).

## 2. Job por registro — `app/jobs/tasks/notify_due_task_job.rb`

```ruby
module Tasks
  class NotifyDueTaskJob < ApplicationJob
    queue_as :default

    def perform(task)
      return if task.reminder_sent_at.present? || task.completed_at.present?

      NotificationBuilder.new(
        notification_type: 'task_due',
        user: task.assignee,
        account: task.account,
        primary_actor: task
      ).perform

      task.update_column(:reminder_sent_at, Time.zone.now)
    end
  end
end
```

`update_column` (não `update!`) de propósito: não deve disparar `dispatch_updated_event`/
broadcast ActionCable (task 05) por causa de um campo interno de bookkeeping que a UI não
precisa saber. Dupla checagem de `reminder_sent_at`/`completed_at` no início do `perform` cobre
o caso de dois jobs para a mesma tarefa serem enfileirados antes do primeiro terminar (o
orquestrador roda a cada 5 min; se o processamento de um batch anterior atrasar, evita
notificação duplicada).

## 3. Registrar no orquestrador central

`app/jobs/trigger_scheduled_items_job.rb` — adicionar uma linha ao `perform` (é core, não
Enterprise, então entra direto, sem `prepend_mod_with`):

```ruby
def perform
  # ... linhas existentes ...

  # Job to notify users about due tasks
  Tasks::TriggerDueTasksJob.perform_later
end
```

## 4. Reset de `reminder_sent_at` ao reagendar

No model `Task` (task 01), adicionar (referenciado como pendência no controller da task 02):

```ruby
before_save :reset_reminder_if_rescheduled

private

def reset_reminder_if_rescheduled
  self.reminder_sent_at = nil if due_date_changed? && reminder_sent_at.present?
end
```
Sem isso, uma tarefa reagendada depois de já ter notificado nunca mais dispara (risco #2 da
visão geral).

## 5. `NotificationBuilder` — nenhuma mudança necessária

`app/builders/notification_builder.rb` já cobre o fluxo genérico (`user.notifications.create!`).
O único `return` condicional hoje é específico de `conversation_creation`
(`notification_builder.rb:27`) — não afeta `task_due`. Conferir que `primary_actor.contact`
funciona para `Task` (task 01 já garante `Task#contact` via `belongs_to`), já que
`build_notification` chama `primary_actor.contact.blocked?` (`notification_builder.rb:29`) —
mesmo guard que hoje só se aplica a conversas, mas funciona igual para `Task` (não notifica
follow-up de contato bloqueado).

## Testes

Só se pedirem. Quando pedido: tarefa com `due_date` no passado e `reminder_sent_at: nil` gera
`Notification` para o assignee; tarefa já `completed_at` presente não gera nada; tarefa já
`reminder_sent_at` presente não gera de novo; reagendar `due_date` limpa `reminder_sent_at`.

## Critério de pronto

- Rodar manualmente `Tasks::TriggerDueTasksJob.perform_now` numa base local com uma tarefa
  `due_date: 1.hour.ago` cria uma `Notification` visível na caixa de entrada do assignee.
- `bundle exec rubocop -a` sem novos warnings.
