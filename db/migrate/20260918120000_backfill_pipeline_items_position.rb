class BackfillPipelineItemsPosition < ActiveRecord::Migration[7.1]
  # Legacy data migration (task 24): every card born before PipelineItem#assign_position was
  # added shares position 0 with every other card in its stage (15 of 21 in dev). Renumbers each
  # stage 0..n-1 in the same (position, id) order the board already reads by (task 14) - the
  # displayed order doesn't change, only the previously-tied values spread out.
  def up
    execute <<~SQL.squish
      WITH ranked AS (
        SELECT id, ROW_NUMBER() OVER (
          PARTITION BY pipeline_stage_id ORDER BY position, id
        ) - 1 AS new_position
        FROM pipeline_items
      )
      UPDATE pipeline_items
      SET position = ranked.new_position
      FROM ranked
      WHERE pipeline_items.id = ranked.id
        AND pipeline_items.position != ranked.new_position
    SQL
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
