class BackfillPipelineStageTypes < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  # stage_type integers: normal=0, start=1, won=2, lost=3
  def up
    Pipeline.find_each do |pipeline|
      stages = pipeline.pipeline_stages.order(:position).to_a
      next if stages.empty?

      stages.first.update_column(:stage_type, 1)

      won_stage = stages.find { |s| s.name.match?(/\A(ganho|won)\z/i) }
      if won_stage
        won_stage.update_column(:stage_type, 2)
      else
        pipeline.pipeline_stages.create!(
          name: 'Ganho', color: '#1f9e51',
          position: (stages.map(&:position).max || 0) + 1,
          stage_type: 2, account_id: pipeline.account_id
        )
      end

      lost_stage = stages.find { |s| s.name.match?(/\A(perdido|lost)\z/i) }
      if lost_stage
        lost_stage.update_column(:stage_type, 3)
      else
        pipeline.pipeline_stages.create!(
          name: 'Perdido', color: '#e35b5b',
          position: (pipeline.pipeline_stages.maximum(:position) || 0) + 1,
          stage_type: 3, account_id: pipeline.account_id
        )
      end
    end
  end

  def down
    PipelineStage.update_all(stage_type: 0)
  end
end
