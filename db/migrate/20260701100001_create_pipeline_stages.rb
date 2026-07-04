class CreatePipelineStages < ActiveRecord::Migration[7.1]
  def change
    create_table :pipeline_stages do |t|
      t.references :account, null: false, index: true
      t.references :pipeline, null: false, index: true
      t.string :name, null: false, limit: 255
      t.string :color, null: false, default: '#1f93ff', limit: 10
      t.integer :position, null: false, default: 0
      t.timestamps
    end
    add_index :pipeline_stages, [:pipeline_id, :name], unique: true
    add_index :pipeline_stages, [:pipeline_id, :position]
  end
end
