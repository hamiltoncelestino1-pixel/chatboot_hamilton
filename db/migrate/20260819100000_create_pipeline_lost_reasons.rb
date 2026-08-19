class CreatePipelineLostReasons < ActiveRecord::Migration[7.1]
  def change
    create_table :pipeline_lost_reasons do |t|
      t.string :title, null: false
      t.references :account, null: false, foreign_key: true

      t.timestamps
    end
    add_index :pipeline_lost_reasons, [:account_id, :title], unique: true
  end
end
