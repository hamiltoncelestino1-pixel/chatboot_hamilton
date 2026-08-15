# Task 01 — Backend: migration + model `Task`

Parte do Grupo A ([visão geral](00-visao-geral.md)). Sem dependências — pode começar primeiro.

## Objetivo

Criar a tabela `tasks` e o model `Task`, seguindo a mesma forma de associação que
`PipelineItem` já usa para "pertencer a vários contextos" (`app/models/pipeline_item.rb:40-53`):
um `contact` obrigatório, `conversation`/`pipeline_item` opcionais. Nenhum polimorfismo — ver
justificativa na visão geral.

## 1. Migration

Novo arquivo `db/migrate/<timestamp>_create_tasks.rb`. Ler
`db/migrate/20260701100004_add_assignee_and_team_to_pipeline_items.rb` antes, para reaproveitar
o idiom de `add_reference`/`add_foreign_key` já usado no projeto.

```ruby
class CreateTasks < ActiveRecord::Migration[7.1]
  def change
    create_table :tasks do |t|
      t.string :title, null: false
      t.datetime :due_date, null: false
      t.datetime :completed_at
      t.datetime :reminder_sent_at

      t.references :account, null: false, foreign_key: true
      t.references :contact, null: false, foreign_key: true
      t.references :conversation, foreign_key: true
      t.references :pipeline_item, foreign_key: true
      t.references :assignee, null: false, foreign_key: { to_table: :users }

      t.timestamps
    end

    # Índice parcial para a query do job periódico (task 04): só tarefas pendentes de
    # notificação entram na varredura, independente de quantas contas/tarefas existam.
    add_index :tasks, :due_date,
              where: 'completed_at IS NULL AND reminder_sent_at IS NULL',
              name: 'index_tasks_on_due_date_pending_reminder'
  end
end
```

`account_id`/`contact_id`/`assignee_id` obrigatórios; `conversation_id`/`pipeline_item_id`
opcionais (tarefa pode nascer só do perfil do contato).

## 2. Model `app/models/task.rb`

```ruby
class Task < ApplicationRecord
  belongs_to :account
  belongs_to :contact
  belongs_to :conversation, optional: true
  belongs_to :pipeline_item, optional: true
  belongs_to :assignee, class_name: 'User'

  validates :title, presence: true
  validates :due_date, presence: true
  validate :conversation_must_belong_to_contact, if: -> { conversation_id.present? }
  validate :pipeline_item_must_belong_to_contact, if: -> { pipeline_item_id.present? }

  scope :pending, -> { where(completed_at: nil) }

  after_create_commit :dispatch_created_event
  after_update_commit :dispatch_completed_event, if: :saved_change_to_completed_at?
  after_update_commit :dispatch_updated_event, if: :broadcast_relevant_change?
  after_destroy_commit :dispatch_deleted_event

  def completed?
    completed_at.present?
  end

  def push_event_data
    {
      id: id,
      title: title,
      due_date: due_date.to_i,
      completed_at: completed_at&.to_i,
      created_at: created_at.to_i,
      updated_at: updated_at.to_i,
      contact_id: contact_id,
      conversation_id: conversation_id,
      pipeline_item_id: pipeline_item_id,
      assignee: assignee.push_event_data
    }
  end

  private

  def conversation_must_belong_to_contact
    return if conversation&.contact_id == contact_id

    errors.add(:conversation_id, I18n.t('errors.task.conversation_contact_mismatch'))
  end

  def pipeline_item_must_belong_to_contact
    return if pipeline_item&.contact_id == contact_id

    errors.add(:pipeline_item_id, I18n.t('errors.task.pipeline_item_contact_mismatch'))
  end

  # Mesmo mirror de PipelineItem#conversation_must_belong_to_contact
  # (app/models/pipeline_item.rb:183-187): evita task apontando para conversa/card de outro
  # contato, o que quebraria a suposição de "contact_id sempre coerente com os outros dois".

  def broadcast_relevant_change?
    saved_change_to_due_date? || saved_change_to_title? || saved_change_to_assignee_id?
  end

  def dispatch_created_event
    Rails.configuration.dispatcher.dispatch(
      Events::Types::TASK_CREATED, Time.zone.now, task: self, performed_by: Current.executed_by
    )
  end

  def dispatch_updated_event
    Rails.configuration.dispatcher.dispatch(
      Events::Types::TASK_UPDATED, Time.zone.now, task: self, performed_by: Current.executed_by
    )
  end

  def dispatch_completed_event
    Rails.configuration.dispatcher.dispatch(
      Events::Types::TASK_COMPLETED, Time.zone.now, task: self, performed_by: Current.executed_by
    )
  end

  def dispatch_deleted_event
    Rails.configuration.dispatcher.dispatch(
      Events::Types::TASK_DELETED, Time.zone.now,
      task_data: { id: id, account_id: account_id, contact_id: contact_id,
                   conversation_id: conversation_id, pipeline_item_id: pipeline_item_id }
    )
  end
end
```

Os eventos `Events::Types::TASK_*` são criados na task 05 (junto com o listener que os
consome) — o model já referencia as constantes, mas só compila/funciona depois da task 05. Se
implementar 01 isoladamente, adicionar as 4 constantes em `lib/events/types.rb` como stub nesta
mesma task é aceitável (evita quebrar o model antes da 05 rodar).

**Nota sobre `dispatch_deleted_event`**: segue o mesmo padrão de `Notification#dispatch_destroy_event`
(`app/models/notification.rb:182-193`) — passa dados serializados, não o objeto ActiveRecord, para
não quebrar quando o `AsyncDispatcher` processar o evento depois que o registro já foi destruído.

## 3. Associação reversa em `Account`/`Contact`/`Conversation`/`PipelineItem`

- `app/models/account.rb` — `has_many :tasks, dependent: :destroy_async` (padrão já usado por
  quase toda associação de `Account`, ver `account.rb:65,89-91`).
- `app/models/contact.rb` — `has_many :tasks, dependent: :destroy_async` (mesmo padrão de
  `has_many :notes`/`has_many :pipeline_items` já existentes, `contact.rb:64-65`).
- `app/models/conversation.rb` e `app/models/pipeline_item.rb` — `has_many :tasks, dependent:
  :nullify` (**não** `:destroy_async` — apagar uma conversa ou um card não deveria apagar a
  tarefa que ficou registrada como follow-up; só desvincula, mantendo `contact_id`).

## 4. i18n dos erros de validação

`config/locales/en.yml` (só `en`, domínio novo, não é Kanban/automation/macros):
```yaml
errors:
  task:
    conversation_contact_mismatch: "Conversation does not belong to the task's contact."
    pipeline_item_contact_mismatch: "Pipeline card does not belong to the task's contact."
```

## Testes

Só escrever `spec/models/task_spec.rb` se pedirem explicitamente (regra do `AGENTS.md`). Quando
pedido, cobrir: presença de `title`/`due_date`, os dois validates de coerência com `contact_id`,
`scope :pending`, e que os 4 eventos disparam nas condições certas (`saved_change_to_*`).

## Critério de pronto

- Migration roda limpo (`bundle exec rails db:migrate`).
- `Task.new(title: 'x', due_date: 1.day.from_now, account:, contact:, assignee:).valid?` → `true`.
- `bundle exec rubocop -a` sem novos warnings nos arquivos tocados.
