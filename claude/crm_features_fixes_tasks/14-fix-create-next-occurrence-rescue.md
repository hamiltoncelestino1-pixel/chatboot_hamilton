# Task 14 — Fix: `create_next_occurrence` sem tratamento de erro (500 pós-persistência)

Severidade: 🟡 Média. Achado na análise técnica de 2026-08-20 (auditoria pós-`df0251e58`).

## Objetivo

`app/models/task.rb:63-64,113-126`:

```ruby
after_update_commit :create_next_occurrence, if: -> { saved_change_to_completed_at? && recurrence_interval.present? }
# ...
def create_next_occurrence
  return if completed_at.blank?

  account.tasks.create!(
    title: title,
    due_date: next_due_date,
    assignee_id: assignee_id,
    contact_id: contact_id,
    conversation_id: conversation_id,
    pipeline_item_id: pipeline_item_id,
    recurrence_interval: recurrence_interval,
    recurrence_parent_id: id
  )
end
```

Roda em `after_update_commit`, sem `rescue`. `pipeline_item_must_belong_to_contact`
(`task.rb:100-104`) valida a nova task; se `pipeline_item_id` copiado apontar pra um card
apagado entre o carregamento da task original em memória e o `complete` (o `dependent:
:nullify` do `PipelineItem` roda um `UPDATE` direto no banco, sem tocar a instância Ruby já
carregada), a validação falha, `create!` lança `RecordInvalid` **dentro do callback**, e a
exceção propaga pra fora do `update!` que o controller já tinha executado com sucesso.

**Efeito**: `app/controllers/api/v1/accounts/tasks_controller.rb#complete` já persistiu a
conclusão da task original (o `update!` comitou, é isso que dispara o callback), mas o
response do controller estoura 500 por causa de uma falha na criação da *próxima* ocorrência —
o agente vê um erro numa ação que, do ponto de vista de dados, já funcionou.

## O que corrigir

Envolver `create_next_occurrence` num tratamento de erro que não deixe a exceção propagar pra
fora do fluxo de conclusão da task original — seguir o mesmo padrão de resiliência já usado
noutros callbacks/services do projeto que reportam pro `ChatwootExceptionTracker` em vez de
estourar (ex. `rescue StandardError => e; ChatwootExceptionTracker.new(exception: e).capture_exception`),
garantindo que a resposta da action `complete` continue `200`/sucesso mesmo se a próxima
ocorrência não puder ser criada. Se fizer sentido pro produto, considerar também notificar o
assignee de alguma forma que a cadeia de recorrência foi interrompida (fora do escopo mínimo,
perguntar se é necessário).

## Testes

Testar manualmente: completar uma task recorrente cujo `pipeline_item_id` aponte pra um card
já apagado (simular deletando o card antes de completar a task) — a conclusão da task deve
retornar sucesso (a task original fica marcada como completa), mesmo que a próxima ocorrência
não seja criada.

## Critério de pronto

- Completar uma task recorrente nunca retorna 500 por causa de falha na criação da próxima
  ocorrência.
- Falha na criação da próxima ocorrência é reportada (Sentry/log), não silenciosamente
  ignorada nem exposta como erro pro usuário numa ação que já teve sucesso.
- `bundle exec rubocop -a` limpo no arquivo tocado.

## Resultado (2026-10-05)

`rescue StandardError` adicionado no **nível do método** `create_next_occurrence`
(`app/models/task.rb:139-148`), reportando pro `ChatwootExceptionTracker` com a conta:

```ruby
rescue StandardError => e
  # This runs in after_update_commit, so an exception escapes the controller's update! and
  # turns an already-persisted completion into a 500 ...
  Rails.logger.error(
    "[Task] create_next_occurrence: task##{id} completed but the next occurrence could not " \
    "be created (#{e.class}) - the recurrence chain stops here"
  )
  ChatwootExceptionTracker.new(e, account: account).capture_exception
end
```

### Duas correções ao texto desta task

1. O snippet sugerido acima (`## O que corrigir`) usa
   `ChatwootExceptionTracker.new(exception: e)` — **assinatura errada**. A real é posicional:
   `new(exception, user: nil, account: nil)` (`lib/chatwoot_exception_tracker.rb`). Passar
   `account:` é o que faz o Sentry agrupar o erro na conta certa.
2. `capture_exception` **já faz `Rails.logger.error`** internamente quando não há DSN de Sentry
   configurado. O `Rails.logger.error` explícito foi mantido de propósito ainda assim: o do
   tracker loga só o `e.message`, sem o `task#id` nem a informação de que a cadeia de
   recorrência parou ali — que é justamente o que alguém investigando "por que minha task
   recorrente sumiu?" precisa ver no log.

### Decisão de produto: não notificar o assignee

A task deixava em aberto ("perguntar se é necessário") notificar o agente de que a cadeia foi
interrompida. **Decidido não fazer** (aprovado pelo usuário): exigiria um
`NOTIFICATION_TYPE` novo, com mailer + template liquid + i18n nos 58 locales (ver regra de
memória `project_notification-type-mailer-i18n-gaps`), para um caso de borda cujo único
disparo conhecido é um card apagado em corrida com a conclusão. Log + Sentry resolvem o
requisito do critério de pronto ("reportada, não silenciosamente ignorada").

### Verificação empírica — as duas metades

Cenário exato da task reproduzido via `rails runner`: cria card → cria task recorrente ligada a
ele → `card.destroy!` (o `dependent: :nullify` do `PipelineItem` zera a coluna no banco **sem
tocar a instância Ruby já carregada**) → completa a task.

**Com o `rescue` removido temporariamente** (prova de que o bug é real e que o fix é o que o
evita):

```
  task#44 criada com pipeline_item_id=116406
  card apagado. instancia em memoria ainda tem pipeline_item_id=116406
  no banco a coluna virou: nil
  RESULTADO: update! LEVANTOU ActiveRecord::RecordInvalid: Validation failed:
             Pipeline item Pipeline card does not belong to the task's contact.
  task concluida no banco? true      <- o 500 pós-persistência, exatamente como descrito
```

**Com o `rescue` restaurado:**

```
  task#45 criada com pipeline_item_id=116407
  card apagado. instancia em memoria ainda tem pipeline_item_id=116407
  no banco a coluna virou: nil
  RESULTADO: update! NAO levantou excecao  <- correcao funcionando
  task concluida no banco? true
  proxima ocorrencia criada? 0 (esperado 0)
  total de tasks mudou? 0
```

E a falha **aparece no log** em vez de ser engolida:

```
[Task] create_next_occurrence: task#45 completed but the next occurrence could not be
created (ActiveRecord::RecordInvalid) - the recurrence chain stops here
```

Note o contraste entre as duas execuções: nos dois casos `task concluida no banco? true` — a
conclusão sempre foi persistida. A única diferença é se o agente recebe 200 ou 500 por uma
ação que, em dados, já tinha funcionado.

**Rubocop:** `1 file inspected, no offenses detected`. Arquivo em LF puro (0 bytes CR,
conferido por contagem de bytes — `od -c | grep '\r'` dá falso positivo neste shell e não
serve de diagnóstico).
