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

    # Partial index for the periodic reminder job (task 04): only tasks still pending
    # notification enter the scan, regardless of how many accounts/tasks exist.
    add_index :tasks, :due_date,
              where: 'completed_at IS NULL AND reminder_sent_at IS NULL',
              name: 'index_tasks_on_due_date_pending_reminder'
  end
end
