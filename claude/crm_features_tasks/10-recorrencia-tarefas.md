# Task 10 — Recorrência de tarefas

Feature 6. Sem dependências, mais nova (sem precedente direto no projeto).

## Decisão já confirmada com o usuário

A próxima ocorrência de uma task recorrente só é criada **ao completar** a atual — não por
job periódico independente que roda mesmo se a task não for concluída.

## Decisão a confirmar no início da implementação

Callback direto no model (`Task`) vs. listener reagindo ao evento `TASK_COMPLETED` já
disparado (`app/models/task.rb:54`, `Events::Types::TASK_COMPLETED` via Wisper). Ambos
válidos — recomendação: **callback direto no model**, porque a criação da próxima ocorrência
é parte do mesmo fluxo síncrono de "completar a task" (não precisa do round-trip
assíncrono do dispatcher), e há precedente direto disso no projeto:
`SlaEvent#create_notifications` (`enterprise/app/models/sla_event.rb:64-86`, citado em
`claude/tasks_tasks/00-visao-geral.md`) também age direto num callback em vez de via
Wisper para esse tipo de efeito colateral imediato.

## Estado atual (confirmado por leitura de código)

- Schema de `Task` (`db/migrate/20260814120000_create_tasks.rb`,
  `app/models/task.rb`) não tem nenhum campo de recorrência.
- Não existe precedente de "recorrência por registro" no projeto — o único padrão de
  recorrência existente é infraestrutural (`sidekiq-cron` via `config/schedule.yml`, jobs
  globais, não por registro).
- `Task` já dispara `after_update_commit :dispatch_completed_event, if:
  :saved_change_to_completed_at?` (`app/models/task.rb:54`).

## O que criar

1. Migration:
   ```ruby
   add_column :tasks, :recurrence_interval, :string # 'daily' | 'weekly' | 'monthly' | nil
   add_column :tasks, :recurrence_parent_id, :bigint
   add_foreign_key :tasks, :tasks, column: :recurrence_parent_id
   ```
2. `app/models/task.rb`:
   ```ruby
   belongs_to :recurrence_parent, class_name: 'Task', optional: true
   RECURRENCE_INTERVALS = %w[daily weekly monthly].freeze
   validates :recurrence_interval, inclusion: { in: RECURRENCE_INTERVALS }, allow_nil: true

   after_update_commit :create_next_occurrence, if: -> { saved_change_to_completed_at? && recurrence_interval.present? }

   private

   def create_next_occurrence
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

   def next_due_date
     case recurrence_interval
     when 'daily' then due_date + 1.day
     when 'weekly' then due_date + 1.week
     when 'monthly' then due_date + 1.month
     end
   end
   ```
   (conferir se `create_next_occurrence` deve rodar mesmo se a task for "descompletada"
   depois — `saved_change_to_completed_at?` dispara em qualquer mudança do campo, inclusive
   de preenchido pra `nil`; adicionar guarda `if completed_at.present?` dentro do método
   para só criar a próxima ocorrência quando a task foi de fato marcada como concluída, não
   ao reabri-la).
3. `TasksController#create_params`/`update_params`
   (`app/controllers/api/v1/accounts/tasks_controller.rb:46-52`) — permitir
   `recurrence_interval`.
4. Frontend: componente compartilhado de form de task (`claude/tasks_tasks/07-*.md`) —
   campo de seleção de recorrência (nenhuma/diária/semanal/mensal).
5. i18n em `tasks.json` (só `en` — não está na exceção kanban/automation/macros, confirmado
   pela task 12 do épico original de Tasks).

## Riscos

- Task recorrente **excluída** (não completada): a série simplesmente para, sem gerar
  próxima ocorrência — não precisa de lógica extra pra esse caso.
- Editar `due_date` de uma ocorrência futura não deveria quebrar a recorrência — cada
  ocorrência já criada é independente, só o `recurrence_interval` é copiado adiante; não
  complicar isso na v1.

## Testes

Testar manualmente no Docker local: criar uma task com `recurrence_interval: 'weekly'`,
completá-la, confirmar que uma nova task é criada automaticamente com `due_date` = due_date
antiga + 7 dias, mesmo assignee/contato/pipeline_item, e `recurrence_parent_id` apontando
pra task original. Testar também reabrir a task original (`completed_at` voltando a `nil`)
e confirmar que isso **não** gera uma segunda ocorrência.

## Critério de pronto

- Completar uma task recorrente cria a próxima ocorrência automaticamente, uma única vez.
- Reabrir uma task já completada não duplica a criação.
- Task não-recorrente (sem `recurrence_interval`) continua funcionando exatamente como
  antes.
- `bundle exec rubocop -a` / `pnpm eslint:fix` limpos nos arquivos tocados.
