class AddRecurrenceToTasks < ActiveRecord::Migration[7.1]
  def change
    add_column :tasks, :recurrence_interval, :string
    add_column :tasks, :recurrence_parent_id, :bigint
    add_index :tasks, :recurrence_parent_id
    add_foreign_key :tasks, :tasks, column: :recurrence_parent_id
  end
end
