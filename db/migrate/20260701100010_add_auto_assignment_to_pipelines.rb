class AddAutoAssignmentToPipelines < ActiveRecord::Migration[7.1]
  def change
    add_column :pipelines, :enable_auto_assignment, :boolean, null: false, default: false
    add_column :pipelines, :max_assignment_limit, :integer, null: false, default: 0
  end
end
