class CreatePipelineItems < ActiveRecord::Migration[7.1]
  def change
    create_table :pipeline_items do |t|
      t.references :account, null: false, index: true
      t.references :pipeline_stage, null: false, index: true
      t.references :contact, null: false, index: true
      t.references :conversation, null: true, index: true
      t.string :title, limit: 255
      t.decimal :value, precision: 15, scale: 2, default: 0
      t.text :notes
      t.integer :position, null: false, default: 0
      t.timestamps
    end
    add_index :pipeline_items, [:pipeline_stage_id, :position]
    add_index :pipeline_items, [:account_id, :contact_id]
  end
end
