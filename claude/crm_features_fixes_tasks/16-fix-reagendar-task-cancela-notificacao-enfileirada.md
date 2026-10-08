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

## Resultado (2026-10-05)

Dois guards acrescentados em `Tasks::NotifyDueTaskJob#perform`
(`app/jobs/tasks/notify_due_task_job.rb:10-16`), e o comentário das linhas 5-8 reescrito — ele
afirmava que "só `completed_at` ainda precisa ser checado", o que deixou de ser verdade.

```ruby
return if task.completed_at.present?
return if task.due_date > Time.current
return if task.reminder_sent_at.blank?
```

### Não precisou cancelar job nenhum do Sidekiq

A primeira leitura desta task sugeria rastrear `job_id` para cancelar o job enfileirado — **não
é necessário**. `perform_later` serializa a task por GlobalID e o worker **relê a linha do
banco** na hora de executar, então o job já vê o `due_date`/`reminder_sent_at` atualizados; e
`ApplicationJob` já tem `discard_on ActiveJob::DeserializationError`
(`app/jobs/application_job.rb:3`) para o caso de a task ter sido apagada nesse meio-tempo. O fix
é revalidação no momento da execução, não cancelamento.

### Por que dois guards, e não só o que a task pede

| Guard | Cenário que impede |
|---|---|
| `due_date > Time.current` | O da task: reagendada **pro futuro** entre o claim e a execução. |
| `reminder_sent_at.blank?` | Reagendada pra **outra data no passado**: segue vencida (o guard acima deixa passar), mas `Task#reset_reminder_if_rescheduled` zerou o claim, e o cron roda **a cada 5 minutos** (`config/schedule.yml:14-16`) → reivindica de novo e notifica. Sem este guard o agente é notificado **duas vezes**. |

Invariante conferido: `Tasks::NotifyDueTaskJob` tem um **único** enfileirador
(`trigger_due_tasks_job.rb:15`, alcançado via `TriggerScheduledItemsJob`) e `reminder_sent_at`
um **único** ponto que limpa (`task.rb:115`) — então `blank?` no momento da execução só pode
significar "foi reagendada depois do claim".

Sob esse invariante o segundo guard engloba o primeiro (reagendar pro futuro também limpa o
claim). Os dois foram mantidos de propósito: expressam intenções distintas e o primeiro sobrevive
a uma escrita que pule callbacks (`update_column(:due_date, ...)`, SQL direto, console).
Aprovado pelo usuário antes de implementar.

### Verificação empírica

Script de `rails runner` percorrendo o **caminho real** de produção em cada cenário —
`Tasks::NotifyDueTaskJob.new(task).serialize` (enfileiramento) → mutação no banco (o agente
agindo enquanto o job espera na fila) → `ActiveJob::Base.execute(payload)` (worker
deserializando com leitura fresca do banco + executando). Contagem por
`Notification.where(primary_actor_type: 'Task', primary_actor_id: task.id)`.

**Com o fix:**

```
  OK     A) vencida, sem reagendar                  notificacoes=1 (esperado 1)
  OK     B) reagendada pro FUTURO                   notificacoes=0 (esperado 0)
  OK     C) reagendada pra outro dia PASSADO        notificacoes=0 (esperado 0)
  OK     D) concluida antes do job rodar            notificacoes=0 (esperado 0)
```

**Com os dois guards novos removidos** (prova de que os bugs são reais e de que são estes guards
que os evitam):

```
  OK     A) vencida, sem reagendar                  notificacoes=1 (esperado 1)
  FALHOU B) reagendada pro FUTURO                   notificacoes=1 (esperado 0)
  FALHOU C) reagendada pra outro dia PASSADO        notificacoes=1 (esperado 0)
  OK     D) concluida antes do job rodar            notificacoes=0 (esperado 0)
```

A e D idênticos nas duas execuções: o caminho feliz e a checagem pré-existente de `completed_at`
não regrediram.

**Enterprise:** nenhum override de `Tasks::NotifyDueTaskJob` em `enterprise/` (o
`enterprise/lib/tasks` são rake tasks, não o model `Task`) — risco 5 da visão geral descartado
para esta task.

**Rubocop:** `1 file inspected, no offenses detected`, após normalizar o arquivo de CRLF para LF
— **5ª ocorrência** do problema nesta base (o `Edit` reescreveu o arquivo inteiro em CRLF).
