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

## Resultado (2026-10-05)

`update_column` trocado por `update_all` condicional nos dois jobs, com os comentários
reescritos (descreviam só o cenário sequencial):

```ruby
# trigger_due_tasks_job.rb
next unless Task.where(id: task.id, reminder_sent_at: nil)
                .update_all(reminder_sent_at: Time.zone.now) == 1

# trigger_stale_items_job.rb
next unless PipelineItem.where(id: item.id, stale_alert_sent_at: nil)
                        .update_all(stale_alert_sent_at: Time.zone.now) == 1
```

### Correção ao texto desta task

A task diz que o `TriggerStaleItemsJob` "replicou o padrão original". Replicou o
claim-antes-de-enfileirar, mas **sem nem o `next unless`** — era um `item.update_column(...)`
solto, cujo retorno ninguém olhava. Então lá o guard não era ineficaz: ele não existia. Agora
existe.

### Três pontos verificados antes de mexer

1. **O `rubocop:disable Rails/SkipsModelValidations` continua necessário** — o cop pega
   `update_all` também, não só `update_column`.
2. **A instância em memória deixa de ser atualizada** (diferença real entre `update_column` e
   `update_all`), e isso não afeta nada: os dois jobs enfileiram com `perform_later`, que
   serializa só o GlobalID, e o worker relê do banco. Importa especialmente porque a
   [task 16](16-fix-reagendar-task-cancela-notificacao-enfileirada.md) ensinou o
   `NotifyDueTaskJob` a checar `reminder_sent_at.blank?` — ele vê o valor **já comitado** pelo
   `update_all`, então os dois fixes compõem corretamente. Confirmado também que
   `NotifyStaleItemJob` lê `pipeline_item.assignee` do registro recarregado.
3. **O `find_each` não pula linhas** apesar de mutarmos a coluna que está no `WHERE` da própria
   query: o cursor é `id > último` e só atualizamos linhas já percorridas. Comportamento
   idêntico ao anterior, não é mudança introduzida aqui.

### Verificação empírica — corrida real, não revisão de código

A task dizia que "revisão de código deve bastar". Dava para provar, e provou-se: duas threads,
cada uma com sua própria conexão, **carregando a linha antes da largada** (imitando duas
execuções do cron que leram a mesma linha antes de qualquer uma comitar) e liberadas juntas por
uma barreira. 5 rodadas por estratégia, com a linha resetada entre elas.

`Task` / `reminder_sent_at`:

```
  FALHOU update_column  vencedores por rodada = [2, 2, 2, 2, 2]
  OK     update_all     vencedores por rodada = [1, 1, 1, 1, 1]
```

`PipelineItem` / `stale_alert_sent_at`:

```
  FALHOU update_column  vencedores por rodada = [2, 2, 2, 2, 2]
  OK     update_all     vencedores por rodada = [1, 1, 1, 1, 1]
```

Com `update_column`, **as duas** execuções passam pelo claim em 100% das rodadas e cada uma
enfileira sua notificação — o cenário descrito na task não é teórico, é reprodutível à vontade.

### Caminho feliz e idempotência

Conferido que o banco local tinha **0** tasks e **0** pipelines elegíveis antes de rodar, para
o `perform_now` não disparar notificações em massa:

```
  due:   claim gravado? true | jobs enfileirados: 1 (esperado 1)
  due:   2a execucao enfileirou: 0 (esperado 0)
  stale: claim gravado? true | jobs enfileirados: 1 (esperado 1)
  stale: 2a execucao enfileirou: 0 (esperado 0)
```

Ou seja: o cenário sequencial que o fix 06 de `crm_optimizacao_tasks/` já resolvia **continua**
resolvido, e agora o concorrente também. O `stale_alert_days` do pipeline de teste foi
restaurado ao valor original (`nil`) ao final.

**Rubocop:** `2 files inspected, no offenses detected`, após normalizar o
`trigger_due_tasks_job.rb` de CRLF para LF (**7ª ocorrência**).
