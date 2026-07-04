class AddCustomAttributesToPipelineItems < ActiveRecord::Migration[7.1]
  def change
    add_column :pipeline_items, :custom_attributes, :jsonb, default: {}, null: false
  end
end
