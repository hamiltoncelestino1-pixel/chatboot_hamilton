# Task 13 — Fix: recorrência mensal — drift do dia do mês em meses curtos

Severidade: 🟡 Média. Achado na análise técnica de 2026-08-20 (auditoria pós-`df0251e58`).
Depende da decisão de produto tomada na task 09.

## Objetivo

`app/models/task.rb:132`: `when 'monthly' then due_date + 1.month`.

Task com `due_date` em 31/jan e `recurrence_interval: monthly`. Ao completar, `due_date +
1.month` vira 28/fev (comportamento padrão de clamping do ActiveSupport, sem erro). Ao
completar essa segunda ocorrência, a próxima soma `+1.month` a partir de 28/fev, gerando
28/mar — não 31/mar. O "dia 31" nunca mais volta em nenhuma ocorrência futura da cadeia, sem
nenhum aviso pro usuário. `swagger/definitions/request/task/create_payload.yml:22-27` só diz
"due the corresponding period after this task's due_date", sem alertar sobre esse drift.

## O que corrigir

Depende de qual semântica foi decidida na task 09:
- Se a task 09 mudou a ancoragem pra "agora"/conclusão, o drift de dia-do-mês ainda pode
  ocorrer (é inerente a somar meses em datas perto do fim do mês), então o mínimo aqui é
  **documentar o comportamento** no Swagger (`create_payload.yml`) e, se fizer sentido pro
  produto, preservar o "dia alvo" original guardando-o separadamente e recalculando a data de
  cada ocorrência a partir desse dia-alvo (em vez de encadear `due_date + 1.month` sobre o
  valor já clampado da ocorrência anterior) — evita o drift permanente, mesmo que ocasionalmente
  caia em fim de mês.
- Confirmar com o usuário se vale o esforço de preservar o dia-alvo (mais robusto, mais
  código) ou se só documentar o comportamento atual já é suficiente (mais simples).

## Testes

Testar manualmente: criar task mensal com `due_date` em 31 de um mês, completar 3-4 vezes
seguidas, confirmar que o comportamento (preservação do dia-alvo ou drift documentado) é o
esperado segundo a decisão tomada.

## Critério de pronto

- Comportamento de recorrência mensal em meses curtos é o decidido com o usuário (preservado
  ou documentado).
- Swagger de `Task` reflete o comportamento real.
- `bundle exec rubocop -a` limpo nos arquivos tocados.

## Decisão e resultado (2026-09-30)

**Decisão de produto: preservar o dia-alvo** (não apenas documentar o drift), via **coluna de
âncora nova**. Escolhida pelo usuário sobre as duas alternativas apresentadas: reapontar
`recurrence_parent_id` para a raiz (sem migration, mas contradiz a descrição do campo no Swagger —
"the task this occurrence was generated from" — e deixaria dados com significado misto) e apenas
documentar o drift (caminho mínimo que a própria task admitia).

Coerente com a decisão da task 09 ("manter a grade"): a mesma filosofia de produto aplicada ao
eixo do dia do mês.

### O que foi feito

1. **Migration** `db/migrate/20260930120000_add_recurrence_anchor_at_to_tasks.rb` —
   `add_column :tasks, :recurrence_anchor_at, :datetime`, **nullable de propósito**: cadeias
   existentes ficam `nil` e caem no comportamento anterior (âncora = próprio `due_date`), então
   **nenhum backfill** é necessário.
2. **`create_next_occurrence`** propaga `recurrence_anchor_at: recurrence_anchor_at || due_date`.
   Na raiz da cadeia o `due_date` dela vira a âncora que todas as seguintes herdam. Guardar no
   registro em vez de subir por `recurrence_parent_id` até a raiz mantém `next_due_date` com uma
   leitura só — uma cadeia diária antiga teria milhares de hops.
3. **`next_due_date`** passou a usar `anchor = recurrence_anchor_at || due_date`.
4. **`before_update :reset_recurrence_anchor, if: :will_save_change_to_due_date?`** — editar o
   `due_date` à mão derruba a âncora, fazendo a cadeia re-ancorar na data nova em vez de voltar
   para a grade original. `before_update` e não `before_save`: na criação o `due_date` sempre
   "muda", e isso apagaria a âncora que o `create_next_occurrence` acabou de definir. Conferido
   que `due_date` só é escrito na criação (controller e `pipeline_item_actions.rb:54`) e pelo
   `update_params` — nenhum job ou service mexe nele, então o callback só dispara em edição real.
5. **Swagger** `request/task/create_payload.yml` — a descrição prometia "due the corresponding
   period after this task's due_date", que a **task 09 tornou falsa**. Reescrita para descrever a
   semântica real: mantém a grade da primeira task da cadeia, pula ocorrências vencidas, e
   re-ancora em edição manual de data.

**`recurrence_anchor_at` ficou fora da API** — conferido que não aparece em `swagger/`,
`app/views/` nem `app/controllers/`. É detalhe de implementação; expor só aumentaria superfície
de contrato.

### Edge case descoberto ao desenhar (e corrigido)

O laço não pode avançar só até `Time.current`. Com âncora da raiz, uma ocorrência concluída
**adiantada** tem âncora mais antiga que o próprio `due_date`, e parar em `Time.current`
devolveria a data em que a task atual já vence — gerando uma ocorrência duplicada. Daí:

```ruby
floor = [Time.current, due_date].max
occurrences += 1 while anchor + (step * occurrences) <= floor
```

### Verificação empírica

**Cadeia mensal ancorada em 31/jan, simulando conclusões mês a mês:**

| Ocorrência | `due_date` | Âncora | Próxima |
|---|---|---|---|
| 1 | 31/jan | 31/jan (raiz) | 28/fev |
| 2 | 28/fev | 31/jan | **31/mar** ← o dia 31 volta |
| 3 | 31/mar | 31/jan | 30/abr |
| 4 | 30/abr | 31/jan | **31/mai** |
| 5 | 31/mai | 31/jan | 30/jun |
| 6 | 30/jun | 31/jan | **31/jul** |

Antes da correção a cadeia ficaria presa em 28 a partir da segunda ocorrência, para sempre.

**Callback de re-ancoramento** (transação com rollback):
```
ancora antes da edicao:  30/Nov/2025 09:00
apos editar SO o titulo: 30/Nov/2025 09:00  <- guard funciona, nao dispara em todo update
apos editar o due_date:  nil                <- re-ancora
```

**Ponta a ponta real** (task criada, concluída, filha inspecionada, ambas removidas depois):
```
pai:   due=21/Sep/2026 ancora=nil            <- raiz
filha: due=02/Oct/2026 ancora=21/Sep/2026    <- herdou a ancora do pai
filha nasceu no futuro? true                 <- comportamento da task 09 intacto
ancora da filha == due do pai? true
```

`rails db:migrate`: aplicada em 0.012s; o gem `annotate` atualizou o bloco de annotation de
`task.rb` automaticamente. `rails swagger:build`: successful. **Rubocop:** `task.rb` e a migration
sem ofensas.

### ⚠️ Dois specs pré-existentes quebrados em `spec/jobs/notification/`

Rodando `spec/jobs/notification/` + specs de pipeline: **32 examples, 2 failures**. Confirmado que
**nenhuma das duas é causada por estas tasks** — substituí `task.rb` e
`remove_duplicate_notification_job.rb` pelas versões do `HEAD` via `git show` e as falhas são
idênticas:

1. `remove_duplicate_notification_job_spec.rb:15` — diagnosticada na task 10: a asserção usa
   `Notification.count` global e o `create(:conversation)` do próprio spec gera uma notificação
   extra via listeners.
2. `remove_old_notification_job_spec.rb:32` — "does not delete notifications when user has fewer
   than 300" falha com `changed from 51 to 50`. Também falha isolada (não é contaminação entre
   arquivos) e também falha no HEAD. Não investigada a fundo — é de um job que estas tasks não
   tocam (`RemoveOldNotificationJob`).

Ambas merecem task própria nesta pasta.
