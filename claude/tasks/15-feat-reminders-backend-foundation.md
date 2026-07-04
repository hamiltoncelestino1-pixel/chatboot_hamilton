# Task: Sistema de Lembretes — Fundação (Schema, Model, Policy)

## Objetivo

Criar o model `Reminder`: título + data/hora de vencimento (`due_at`), opcionalmente vinculado a
uma `Conversation`/`Contact`/`PipelineItem` (polimórfico), opcionalmente atribuído a um agente
específico ou a um time, sempre com um criador (`created_by`). Esta task só cria a fundação de
dados — nenhuma integração com o sistema de notificação ainda (isso é a task
`16-feat-reminders-notification-integration.md`).

**Contexto do produto:** hoje não existe forma de agendar um aviso futuro no Chatwoot além do
snooze de conversa (que não tem título/descrição e não pode ser geral pra um contato/oportunidade).
Decisões já validadas: lembrete "geral" (sem assignee) notifica quem já tem acesso ao registro
vinculado; existirá uma tela dedicada "Lembretes"; sem recorrência nesta primeira versão.

---

## 1. Migração — `db/migrate/*_create_reminders.rb`

```ruby
class CreateReminders < ActiveRecord::Migration[7.1]
  def change
    create_table :reminders do |t|
      t.references :account, null: false, foreign_key: true, index: true
      t.string :title, null: false
      t.text :description
      t.datetime :due_at, null: false
      t.references :remindable, polymorphic: true, index: true, null: true
      t.bigint :assignee_id
      t.bigint :team_id
      t.bigint :created_by_id, null: false
      t.datetime :notified_at
      t.datetime :completed_at
      t.timestamps
    end

    add_foreign_key :reminders, :users, column: :assignee_id
    add_foreign_key :reminders, :users, column: :created_by_id
    add_foreign_key :reminders, :teams, column: :team_id
    add_index :reminders, :assignee_id
    add_index :reminders, :team_id
    add_index :reminders, [:account_id, :due_at]
    add_index :reminders, [:notified_at, :due_at] # usado pelo job de disparo (task 17)
  end
end
```

`remindable_type`/`remindable_id` seguem exatamente o padrão já usado em `Notification#primary_actor`
(`app/models/notification.rb`), `AccessToken#owner` e `Message#sender` — `belongs_to ...,
polymorphic: true` com colunas `<nome>_type`/`<nome>_id` e índice composto (gerado automaticamente
por `t.references ..., polymorphic: true, index: true`).

`assignee_id`/`team_id`/`created_by_id` são `bigint` cru (não `t.references`), mesmo padrão já usado
em `pipeline_items.assignee_id`/`team_id` (ver `db/migrate/*_add_assignee_and_team_to_pipeline_items.rb`
da task 08 do módulo Kanban).

Rodar `bundle exec rails db:migrate` e conferir `db/schema.rb`.

---

## 2. Model — `app/models/reminder.rb`

```ruby
class Reminder < ApplicationRecord
  belongs_to :account
  belongs_to :remindable, polymorphic: true, optional: true
  belongs_to :assignee, class_name: 'User', optional: true
  belongs_to :team, optional: true
  belongs_to :created_by, class_name: 'User'

  validates :title, presence: true
  validates :due_at, presence: true
  validate :assignee_must_have_access_to_remindable

  scope :pending, -> { where(completed_at: nil).where('due_at >= ?', Time.current) }
  scope :overdue, -> { where(completed_at: nil).where('due_at < ?', Time.current) }
  scope :completed, -> { where.not(completed_at: nil) }
  scope :due_for_notification, -> { where(notified_at: nil).where(due_at: ..Time.current) }

  def status
    return :completed if completed_at.present?

    due_at < Time.current ? :overdue : :pending
  end

  def mark_as_completed!
    update!(completed_at: Time.current)
  end

  def mark_as_notified!
    update_column(:notified_at, Time.current) # rubocop:disable Rails/SkipsModelValidations
  end

  def push_event_data
    { id: id, title: title, due_at: due_at, meta: { assignee: assignee&.push_event_data } }
  end

  private

  def assignee_must_have_access_to_remindable
    return if assignee_id.blank?
    return if assignee.administrator?

    case remindable_type
    when 'PipelineItem'
      errors.add(:assignee_id, :not_pipeline_member) unless remindable.pipeline.members.exists?(id: assignee_id)
    when 'Conversation'
      errors.add(:assignee_id, :no_conversation_access) unless conversation_assignee_has_access?
    end
    # Contact e lembrete solto (sem remindable): qualquer agente da conta é elegível, sem checagem extra.
  end

  def conversation_assignee_has_access?
    return true if remindable.team_id.present? && remindable.team.members.exists?(id: assignee_id)

    remindable.inbox.members.exists?(id: assignee_id)
  end
end
```

`push_event_data` já devolve o formato `{ meta: { assignee: ... } }` — isso é necessário porque a
tela de Notificações (`NotificationTable.vue`, frontend) lê `primary_actor.meta.assignee` pra
desenhar o avatar da linha, um formato herdado de `Conversation#push_event_data`. Sem isso, uma
notificação de lembrete apareceria sem avatar (não quebra, mas fica inconsistente) — ver task 16.

`account_id` **não** é inferido automaticamente aqui — é preenchido no controller a partir de
`Current.account`, mesmo padrão de `PipelineItem`/`Notification`.

i18n dos erros de validação, em `config/locales/en.yml` (dentro de `errors.messages` ou
`activerecord.errors.models.reminder.attributes.assignee_id`, seguir o padrão já usado por
`not_pipeline_member` — ver task 08 do Kanban, `errors.pipeline_item.assignee_not_member`):

```yaml
activerecord:
  errors:
    models:
      reminder:
        attributes:
          assignee_id:
            not_pipeline_member: 'must be a member of the pipeline'
            no_conversation_access: 'must have access to the conversation'
```

---

## 3. Policy — `app/policies/reminder_policy.rb`

```ruby
class ReminderPolicy < ApplicationPolicy
  def index?
    true
  end

  def show?
    creator_or_assignee_or_admin?
  end

  def create?
    true
  end

  def update?
    creator_or_assignee_or_admin?
  end

  def complete?
    creator_or_assignee_or_admin?
  end

  def destroy?
    record.created_by_id == @user.id || @account_user.administrator?
  end

  private

  def creator_or_assignee_or_admin?
    record.created_by_id == @user.id || record.assignee_id == @user.id || @account_user.administrator?
  end
end
```

Regra: criador sempre pode tudo; assignee pode ver/editar/concluir mas não excluir; admin pode tudo.
A visibilidade fina de *listagem* (quais lembretes aparecem na tela "Lembretes" pra cada usuário)
fica no `ReminderFinder` (task 18), não aqui — mesma separação de responsabilidades já usada entre
`NotificationFinder` e a ausência de uma policy granular para `Notification`.

---

## 4. Associações complementares

**`app/models/account.rb`**: adicionar `has_many :reminders, dependent: :destroy_async`.
**`app/models/user.rb`**: adicionar `has_many :assigned_reminders, class_name: 'Reminder', foreign_key: :assignee_id, dependent: :nullify` e `has_many :created_reminders, class_name: 'Reminder', foreign_key: :created_by_id, dependent: :destroy_async`.

---

## 5. Specs

### `spec/factories/reminders.rb`

Mirror de `spec/factories/notifications.rb` (sintaxe simples, `primary_actor { create(:conversation,
account: account) }` como referência):

```ruby
FactoryBot.define do
  factory :reminder do
    account
    created_by { association :user }
    title { 'Follow up with customer' }
    due_at { 1.day.from_now }
    notified_at { nil }
    completed_at { nil }

    trait :with_assignee do
      assignee { association :user }
    end

    trait :for_conversation do
      remindable { create(:conversation, account: account) }
    end

    trait :for_contact do
      remindable { create(:contact, account: account) }
    end

    trait :for_pipeline_item do
      remindable { create(:pipeline_item, account: account) }
    end

    trait :completed do
      completed_at { 1.hour.ago }
    end

    trait :overdue do
      due_at { 1.day.ago }
    end

    trait :notified do
      notified_at { Time.current }
    end
  end
end
```

(Confirmar se já existem factories `:pipeline_item`/`:conversation`/`:contact` com a assinatura
usada acima — devem existir, dado que os módulos de Kanban e o core do Chatwoot já têm specs.)

### `spec/models/reminder_spec.rb`

Cobrir: validações de presence (`title`, `due_at`); `assignee_must_have_access_to_remindable` nos
3 cenários (PipelineItem com/sem membership, Conversation com/sem acesso via inbox/team, Contact
sempre permite); os scopes `pending`/`overdue`/`completed`/`due_for_notification`; o método `status`
nos 3 estados.

---

## Verificação

```ruby
# rails console
account = Account.first
agent = account.users.first
reminder = Reminder.create!(
  account: account, title: 'Ligar pro cliente', due_at: 1.day.from_now,
  created_by: agent, assignee: agent
)
reminder.status # => :pending
reminder.due_at = 1.hour.ago
reminder.save!
reminder.status # => :overdue
reminder.mark_as_completed!
reminder.status # => :completed
```

1. Rodar `bundle exec rspec spec/models/reminder_spec.rb` — tudo verde.
2. Tentar criar um `Reminder` vinculado a uma oportunidade (`PipelineItem`) com `assignee` que **não**
   é membro do pipeline — deve falhar a validação.
3. Tentar o mesmo com um agente que É membro — deve salvar normalmente.
