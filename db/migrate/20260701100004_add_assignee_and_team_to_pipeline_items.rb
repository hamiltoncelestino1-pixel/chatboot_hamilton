class AddAssigneeAndTeamToPipelineItems < ActiveRecord::Migration[7.1]
  def change
    add_column :pipeline_items, :assignee_id, :bigint
    add_column :pipeline_items, :team_id, :bigint
    add_index :pipeline_items, :assignee_id
    add_index :pipeline_items, :team_id
    add_foreign_key :pipeline_items, :users, column: :assignee_id
    add_foreign_key :pipeline_items, :teams
  end
end
