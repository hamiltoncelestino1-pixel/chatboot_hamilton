class BackfillStageChangedAtOnPipelineItems < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def up
    execute <<-SQL.squish
      UPDATE pipeline_items
      SET stage_changed_at = created_at
      WHERE stage_changed_at IS NULL
    SQL
  end

  def down
    # no-op: backfill is not reversible and stage_changed_at column removal is handled by its own migration
  end
end
