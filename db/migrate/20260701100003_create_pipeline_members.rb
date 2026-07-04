class CreatePipelineMembers < ActiveRecord::Migration[7.1]
  def change
    create_table :pipeline_members do |t|
      t.bigint :pipeline_id, null: false
      t.bigint :user_id, null: false
      t.timestamps
    end
    add_index :pipeline_members, [:pipeline_id, :user_id], unique: true
    add_index :pipeline_members, :user_id
    add_foreign_key :pipeline_members, :pipelines
    add_foreign_key :pipeline_members, :users
  end
end
