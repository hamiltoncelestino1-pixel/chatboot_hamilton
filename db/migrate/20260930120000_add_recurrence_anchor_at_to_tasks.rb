class AddRecurrenceAnchorAtToTasks < ActiveRecord::Migration[7.1]
  def change
    # Anchor the whole recurrence chain to the date the user originally picked, so a monthly
    # task due on the 31st keeps landing on the 31st instead of being clamped down to 28 by
    # February and never recovering. Nullable on purpose: existing chains stay nil and fall
    # back to anchoring on their own due_date, which is exactly today's behaviour, so no
    # backfill is needed.
    add_column :tasks, :recurrence_anchor_at, :datetime
  end
end
