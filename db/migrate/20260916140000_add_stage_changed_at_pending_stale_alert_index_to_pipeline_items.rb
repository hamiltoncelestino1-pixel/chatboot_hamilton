class AddStageChangedAtPendingStaleAlertIndexToPipelineItems < ActiveRecord::Migration[7.1]
  def change
    # Partial index for PipelineItems::TriggerStaleItemsJob (task 13): only cards still pending
    # a stale alert and assigned to someone enter the scan, regardless of how many cards exist in
    # the pipeline - same pattern as index_tasks_on_due_date_pending_reminder.
    add_index :pipeline_items, :stage_changed_at,
              where: 'stale_alert_sent_at IS NULL AND assignee_id IS NOT NULL',
              name: 'index_pipeline_items_on_stage_changed_at_pending_stale_alert'
  end
end
