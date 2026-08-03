class AddSyncAssignmentsToPipelines < ActiveRecord::Migration[7.1]
  def change
    add_column :pipelines, :sync_assignments, :boolean, null: false, default: false
  end
end
