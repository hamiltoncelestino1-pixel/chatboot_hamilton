class AddPipelineLostReasonToPipelineItems < ActiveRecord::Migration[7.1]
  def change
    add_reference :pipeline_items, :pipeline_lost_reason, foreign_key: true
  end
end
