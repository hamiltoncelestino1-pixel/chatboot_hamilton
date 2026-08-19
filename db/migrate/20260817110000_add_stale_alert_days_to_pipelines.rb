class AddStaleAlertDaysToPipelines < ActiveRecord::Migration[7.1]
  def change
    add_column :pipelines, :stale_alert_days, :integer
  end
end
