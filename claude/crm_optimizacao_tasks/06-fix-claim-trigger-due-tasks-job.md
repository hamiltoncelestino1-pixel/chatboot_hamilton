# Task 06 — Fix: `TriggerDueTasksJob` sem claim antes de enfileirar

Severidade: 🟠 Alta (risco baixo em volume normal, correção barata). Achado na auditoria de
otimização de CRM (2026-08-16).

## Objetivo

`app/jobs/tasks/trigger_due_tasks_job.rb`:

```ruby
class Tasks::TriggerDueTasksJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    Task.where(reminder_sent_at: nil, completed_at: nil)
        .where(due_date: 3.days.ago..Time.current)
        .find_each(batch_size: 100) do |task|
      Tasks::NotifyDueTaskJob.perform_later(task)
    end
  end
end
```

`reminder_sent_at` só é setado dentro de `Tasks::NotifyDueTaskJob#perform`
(`app/jobs/tasks/notify_due_task_job.rb:15`, depois da notificação ser enviada), **não** no
job de trigger. Se a fila `default` (onde `NotifyDueTaskJob` roda, `queue_as :default`)
atrasar por qualquer motivo e o cron do trigger rodar de novo antes do primeiro
`NotifyDueTaskJob` ser processado, a mesma `Task` (ainda com `reminder_sent_at: nil`) é
selecionada de novo pela query e enfileirada uma segunda vez.

Combinado com o bug da task 01 (push duplicado em retry), isso pode multiplicar o número de
notificações duplicadas enviadas para o mesmo vencimento. Risco baixo em volume normal de
uso, mas a correção é barata.

## O que corrigir

Mover o claim (`update_column(:reminder_sent_at, ...)`, ou um marcador equivalente) para
`TriggerDueTasksJob`, **antes** de enfileirar `NotifyDueTaskJob`, em vez de depois da
notificação ser enviada. Cuidado: isso muda a semântica de "quando reminder_sent_at é
setado" — hoje ele meio que significa "notificação enviada com sucesso"; movendo para o
trigger, passa a significar "processamento iniciado". Duas formas de resolver, escolher uma:

**Opção A (mais simples, recomendada)**: usar `update_all` com condição atômica dentro do
`find_each`, marcando a task como "reivindicada" antes de enfileirar:

```ruby
def perform
  Task.where(reminder_sent_at: nil, completed_at: nil)
      .where(due_date: 3.days.ago..Time.current)
      .find_each(batch_size: 100) do |task|
    next unless task.update_column(:reminder_sent_at, Time.zone.now) # claim atômico por linha

    Tasks::NotifyDueTaskJob.perform_later(task)
  end
end
```
E remover o `task.update_column(:reminder_sent_at, ...)` duplicado de dentro de
`NotifyDueTaskJob#perform` (já não é mais necessário, o claim já aconteceu antes).

**Opção B**: manter o comportamento atual (claim só depois de enviar) e em vez disso reduzir
a janela de corrida usando um lock de linha (`with_lock` ou `SELECT ... FOR UPDATE`) — mais
complexo, só escolher se a Opção A não for aceitável por algum motivo de negócio (ex. se
"reminder_sent_at setado" precisar continuar significando "de fato enviado", não "em
processamento").

Confirmar com o padrão do resto do projeto (`claude/tasks_tasks/00-visao-geral.md` cita que
não existe uso de `perform_at`/`perform_in`, só polling — este fix não muda essa convenção,
só onde o claim acontece).

## Testes

Testar manualmente no Docker local: criar uma task vencida, rodar `TriggerDueTasksJob` duas
vezes seguidas rapidamente (simulando o cron atrasado), confirmar que só 1
`NotifyDueTaskJob` é enfileirado (verificar na fila do Sidekiq, ex. via `sidekiq/web` ou
`Sidekiq::Queue.new('default').size` antes/depois).

## Critério de pronto

- Task vencida não pode ser enfileirada 2x pelo trigger job em execuções consecutivas.
- `NotifyDueTaskJob` continua funcionando normalmente (notificação enviada, task marcada).
- `bundle exec rubocop -a` limpo nos arquivos tocados.
