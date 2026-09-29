# Task 16 — Fix: reagendar task não cancela notificação de vencimento já enfileirada

Severidade: 🟡 Média. Achado na análise técnica de 2026-08-20 (auditoria pós-`df0251e58`).

## Objetivo

`app/models/task.rb:106-108`:

```ruby
def reset_reminder_if_rescheduled
  self.reminder_sent_at = nil if due_date_changed? && reminder_sent_at.present?
end
```

`app/jobs/tasks/notify_due_task_job.rb:4-8` só checa `completed_at`, não relê a janela de
vencimento nem `reminder_sent_at` no momento da execução.

**Cenário concreto**: task vencida ontem é reivindicada pelo `TriggerDueTasksJob`
(`reminder_sent_at` setado) e `NotifyDueTaskJob` é enfileirado — mas a fila `default` está com
backlog. Antes do job rodar, o agente reagenda o `due_date` pra semana que vem;
`reset_reminder_if_rescheduled` zera `reminder_sent_at` corretamente (vai vencer de novo no
futuro, comportamento correto pro próximo ciclo do trigger). Só que o `NotifyDueTaskJob` **já
enfileirado** ainda executa, e como só checa `completed_at` (que continua `nil`), dispara a
notificação "sua tarefa está vencendo" mesmo a task já tendo sido reagendada — confundindo o
agente logo depois de reagendar.

## O que corrigir

`NotifyDueTaskJob#perform` deve checar, além de `completed_at`, se a task ainda está
efetivamente vencida no momento da execução (ex. `due_date <= Time.current`) antes de disparar
a notificação — evita notificar sobre uma task que já foi reagendada pro futuro entre o
enfileiramento e a execução do job.

## Testes

Testar manualmente (ou via `rails console`): simular o cenário — marcar `reminder_sent_at` numa
task vencida, enfileirar `NotifyDueTaskJob` manualmente sem executar ainda, reagendar o
`due_date` da task pro futuro, então executar o job — nenhuma notificação deve ser enviada.

## Critério de pronto

- Reagendar uma task antes do job de notificação rodar cancela efetivamente o envio da
  notificação de vencimento antiga.
- Fluxo normal (task vencida, sem reagendamento) continua notificando normalmente.
- `bundle exec rubocop -a` limpo no arquivo tocado.
