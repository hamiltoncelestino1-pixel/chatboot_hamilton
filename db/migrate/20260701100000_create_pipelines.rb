class CreatePipelines < ActiveRecord::Migration[7.1]
  def change
    create_table :pipelines do |t|
      t.references :account, null: false, index: true
      t.string :name, null: false, limit: 255
      t.text :description
      t.integer :position, null: false, default: 0
      t.timestamps
    end
    add_index :pipelines, [:account_id, :name], unique: true
    add_index :pipelines, [:account_id, :position]
  end
end
