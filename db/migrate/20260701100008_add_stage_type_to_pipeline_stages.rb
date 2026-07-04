class AddStageTypeToPipelineStages < ActiveRecord::Migration[7.1]
  def change
    add_column :pipeline_stages, :stage_type, :integer, null: false, default: 0
  end
end
