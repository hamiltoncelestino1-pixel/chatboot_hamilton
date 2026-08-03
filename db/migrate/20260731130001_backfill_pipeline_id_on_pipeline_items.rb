class BackfillPipelineIdOnPipelineItems < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def up
    execute <<-SQL.squish
      UPDATE pipeline_items
      SET pipeline_id = pipeline_stages.pipeline_id
      FROM pipeline_stages
      WHERE pipeline_stages.id = pipeline_items.pipeline_stage_id
        AND pipeline_items.pipeline_id IS NULL
    SQL
  end

  def down
    # no-op: backfill is not reversible and pipeline_id column removal is handled by its own migration
  end
end
