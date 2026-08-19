class AddStageChangedAtAndStaleAlertSentAtToPipelineItems < ActiveRecord::Migration[7.1]
  def change
    add_column :pipeline_items, :stage_changed_at, :datetime
    add_column :pipeline_items, :stale_alert_sent_at, :datetime
  end
end
