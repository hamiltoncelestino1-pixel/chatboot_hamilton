class AddPipelineIdToPipelineItems < ActiveRecord::Migration[7.1]
  def change
    add_reference :pipeline_items, :pipeline, foreign_key: true, index: true
  end
end
