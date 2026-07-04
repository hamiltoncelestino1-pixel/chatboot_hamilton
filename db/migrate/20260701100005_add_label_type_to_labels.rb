class AddLabelTypeToLabels < ActiveRecord::Migration[7.1]
  def change
    add_column :labels, :label_type, :integer, default: 0, null: false
    add_index :labels, [:label_type, :account_id]
  end
end
