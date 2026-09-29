# Task 19 — Fix: claim de `TriggerDueTasksJob` não é compare-and-swap atômico de verdade

Severidade: 🟢 Baixa. Achado na análise técnica de 2026-08-20 (auditoria pós-`df0251e58`),
como parte da verificação do fix 06 da auditoria anterior (2026-08-16).

## Objetivo

O fix 06 de `claude/crm_optimizacao_tasks/` foi confirmado aplicado corretamente:
`app/jobs/tasks/trigger_due_tasks_job.rb:12` faz
`next unless task.update_column(:reminder_sent_at, Time.zone.now)` antes de enfileirar
`Tasks::NotifyDueTaskJob`, resolvendo o cenário original descrito no fix (segunda execução do
cron depois que a primeira já comitou o claim). O mesmo padrão foi corretamente replicado em
`app/jobs/pipeline_items/trigger_stale_items_job.rb:11`.

Ressalva encontrada nesta nova auditoria: `update_column(:reminder_sent_at, Time.zone.now)`
gera um `UPDATE tasks SET reminder_sent_at = X WHERE id = Y` **sem** `AND reminder_sent_at IS
NULL` na cláusula `WHERE` da própria query. Isso fecha o cenário sequencial (execução B
depois que execução A já comitou), mas não é um compare-and-swap atômico no sentido estrito:
duas execuções genuinamente **concorrentes** de `TriggerDueTasksJob` que leiam a mesma linha
antes de qualquer uma comitar seu claim passariam ambas pela checagem e reenfileirariam a
mesma notificação. Risco baixo — exige duas execuções do próprio trigger job sobrepostas no
tempo, cenário raro dado que o job roda via cron a cada 5 minutos — mas vale registrar porque
a doc do fix 06 descreve a solução como "claim atômico por linha", o que não é 100% preciso
tecnicamente.

## O que corrigir

Trocar o `update_column` por uma atualização condicional que só afeta a linha se
`reminder_sent_at` ainda estiver `NULL` no momento exato da execução, ex.:

```ruby
next unless Task.where(id: task.id, reminder_sent_at: nil)
                .update_all(reminder_sent_at: Time.zone.now) == 1
```

(`update_all` retorna o número de linhas afetadas — `1` confirma que este processo venceu a
corrida; `0` significa que outra execução já reivindicou a linha primeiro.) Aplicar o mesmo
ajuste em `app/jobs/pipeline_items/trigger_stale_items_job.rb:11`, que replicou o padrão
original.

## Testes

Não há como testar concorrência real de forma simples manualmente — revisão de código deve
bastar aqui. Se quiser validar, pode-se simular disparando duas execuções do job quase
simultâneas via `rails console` (duas threads/processos) sobre a mesma task e confirmar que só
uma consegue o claim.

## Critério de pronto

- Claim de `reminder_sent_at` em `TriggerDueTasksJob` e `TriggerStaleItemsJob` é uma
  atualização condicional atômica de verdade (via `update_all` com `WHERE` na coluna de
  claim), não um `update_column` incondicional.
- `bundle exec rubocop -a` limpo nos arquivos tocados.
