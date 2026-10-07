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

## Decisão e resultado (2026-09-30)

**Decisão de produto: opção 2 — manter a grade, pulando as ocorrências vencidas.** Escolhida pelo
usuário sobre a opção 1 (ancorar na conclusão), para preservar a semântica de agenda fixa
("toda segunda-feira").

`next_due_date` reescrito com um contador de passos, e o `case` extraído para
`recurrence_step`, que devolve a `ActiveSupport::Duration`:

```ruby
step = recurrence_step
return if step.nil?

now = Time.current
occurrences = 1
occurrences += 1 while due_date + (step * occurrences) <= now
due_date + (step * occurrences)
```

**Multiplicar o passo pela âncora, em vez de somar a um valor corrente**, é a escolha que evita
introduzir o drift da task 13 dentro de um mesmo salto: encadear `+= 1.month` levaria uma task de
31/jan por 28/fev e perderia o dia 31 no caminho. Medido: `due_date` 31/jan com `now` em 30/set
devolveu **31/out**, ou seja, o dia 31 sobreviveu a 9 passos incluindo fevereiro. Com
encadeamento teria virado 28/out.

**O que continua fora de escopo (task 13):** o drift **entre** ocorrências da cadeia. Cada nova
`Task` nasce com o próprio `due_date` e a seguinte ancora nela, então 31/jan → 28/fev faz a
próxima ancorar em 28/fev. Fechar isso exige a âncora da raiz da cadeia (subir por
`recurrence_parent_id`) ou um dia-alvo persistido. O desenho acima deixa o caminho pronto: basta
a âncora deixar de ser `due_date`.

### Verificação empírica

Não existe spec de `Task` no projeto. `rails runner` no Docker local, com `now` = 30/set 15:35.

**Contraste com a fórmula antiga, contra a janela real do `Tasks::TriggerDueTasksJob`
(`27/Set 15:35 .. 30/Set 15:35`):**

| Cenário | ANTES (`due + 1x`) | Consequência | DEPOIS |
|---|---|---|---|
| atrasada 10d, daily | 21/Set (passado) | fora da janela → **cadeia morre** | 01/Out |
| atrasada 10d, weekly | 27/Set (passado) | na **borda** da janela → morria ou renotificava na hora, por timing de sub-segundo | 04/Out |
| atrasada 10d, monthly | 20/Out | já era futuro — este caso não tinha bug | 20/Out (igual) |
| atrasada 40d, daily | 22/Ago (passado) | fora da janela → **cadeia morre** | 01/Out |
| atrasada 40d, weekly | 28/Ago (passado) | fora da janela → **cadeia morre** | 02/Out |
| atrasada 40d, monthly | 21/Set (passado) | fora da janela → **cadeia morre** | 21/Out |

Em 5 dos 6 cenários a fórmula antiga produzia data no passado, e em todos os 5 a nova produz data
no futuro. O caso `weekly` atrasado 10d caindo exatamente na borda da janela é ilustrativo do
quanto o comportamento antigo era frágil.

**Grade preservada (o ponto da decisão de produto):** os saltos semanais deram +14d e +42d —
múltiplos exatos de 7, o que garante o mesmo dia da semana. Os mensais preservaram o dia do mês
(20 → 20, 21 → 21), visível na saída.

**Sem regressão no caminho normal:** task que vence amanhã, concluída hoje → daily +1d,
weekly +7d, monthly +31d. Exatamente um intervalo à frente, como antes.

**Guard:** `recurrence_interval` desconhecido (`"hourly"`) → `nil`, preservando o comportamento
anterior. Impossível de persistir de todo jeito, pelo `validates :inclusion` da linha 53.

**Rubocop:** `app/models/task.rb` — nenhuma ofensa.
