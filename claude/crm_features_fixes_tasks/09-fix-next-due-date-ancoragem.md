# Task 09 — Fix: recorrência atrasada nunca se recupera (ancoragem de `next_due_date`)

Severidade: 🟠 Alta. Achado na análise técnica de 2026-08-20 (auditoria pós-`df0251e58`).

⚠️ **Esta task exige decisão de produto do usuário antes de implementar** — muda a semântica de
quando uma tarefa recorrente vence. A task 13 (drift de dia em recorrência mensal) depende da
decisão tomada aqui.

## Objetivo

`app/models/task.rb:113-134`:

```ruby
def create_next_occurrence
  return if completed_at.blank?

  account.tasks.create!(
    title: title,
    due_date: next_due_date,
    # ...
  )
end

def next_due_date
  case recurrence_interval
  when 'daily' then due_date + 1.day
  when 'weekly' then due_date + 1.week
  when 'monthly' then due_date + 1.month
  end
end
```

`next_due_date` soma o intervalo ao `due_date` **antigo** da task que acabou de ser concluída,
não a partir de "agora" (`Time.current`) nem da data de conclusão (`completed_at`).

**Cenário concreto**: task diária vencida há 10 dias é completada hoje. `next_due_date` =
`due_date antigo + 1 dia` = ainda 9 dias no passado.
- Se essa data cair dentro da janela de 3 dias que `Tasks::TriggerDueTasksJob` usa
  (`3.days.ago..Time.current`, `app/jobs/tasks/trigger_due_tasks_job.rb:5-6`), a nova task é
  imediatamente repescada pelo próximo ciclo do job (roda a cada 5 min) e dispara notificação
  de "vencida" na hora seguinte à conclusão — o agente acabou de completar uma tarefa e já
  recebe alerta de que a "próxima" já está vencida.
- Se cair **fora** dessa janela de 3 dias, a task nunca mais é selecionada pelo job periódico —
  cada conclusão tardia empurra o `due_date` cada vez mais pro passado, e a cadeia de
  recorrência **para de notificar pra sempre**, sem nenhum erro visível pro agente. A tarefa
  continua existindo (`Task.pending` ainda a inclui), mas fica invisível pro fluxo de
  notificação de vencimento.

## Decisão de produto a confirmar com o usuário antes de codar

Duas semânticas possíveis para "próxima ocorrência":
1. **Ancorar em "agora"/conclusão** (`Time.current + intervalo`, ou `completed_at + intervalo`)
   — a próxima ocorrência sempre vence um intervalo completo a partir de quando a tarefa atual
   foi de fato concluída, independente de atraso. Mais previsível pro agente, mas perde a
   "grade fixa" original (ex. toda segunda-feira) se houver atrasos recorrentes.
2. **Manter ancoragem no `due_date` original, mas pular ocorrências vencidas no passado** —
   soma o intervalo repetidamente até ultrapassar `Time.current` (mantém a grade fixa, ex.
   "toda segunda-feira", mas nunca gera uma ocorrência já nascida vencida).

Recomendação: opção 1 é mais simples e evita todo o problema descrito acima; opção 2 preserva
melhor a intenção original de "toda segunda-feira" para quem usa recorrência como agenda fixa.
Perguntar ao usuário qual semântica é a esperada antes de implementar.

## O que corrigir (após decisão)

Ajustar `next_due_date` conforme a opção escolhida. Se optar pela 2, terá que iterar
(`while next_date <= Time.current; next_date += intervalo; end`) em vez de somar uma única vez.

## Testes

Testar manualmente: completar uma task diária/semanal/mensal com `due_date` bem no passado
(vários dias/semanas de atraso) e confirmar que a nova ocorrência nasce com uma data que faz
sentido segundo a semântica escolhida — e que ela é corretamente repescada pelo
`TriggerDueTasksJob` quando realmente vencer (não antes, não nunca).

## Critério de pronto

- Comportamento de `next_due_date` alinhado à decisão de produto confirmada com o usuário.
- Task recorrente completada com atraso não gera notificação imediata indevida nem para de
  notificar pra sempre.
- `bundle exec rubocop -a` limpo no arquivo tocado.
