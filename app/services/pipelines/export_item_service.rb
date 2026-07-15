class Pipelines::ExportItemService
  pattr_initialize [:pipeline_item!, :target_pipeline!, :target_stage_id!]

  class InvalidTargetStageError < StandardError; end
  class SamePipelineError < StandardError; end

  def perform
    raise SamePipelineError, I18n.t('errors.pipeline_item.export_same_pipeline') if same_pipeline?

    target_stage = fetch_target_stage
    pipeline_item.update!(
      pipeline_stage_id: target_stage.id,
      position: next_position(target_stage),
      assignee_id: exportable_assignee_id(target_pipeline)
    )
    pipeline_item.association(:pipeline_stage).reset
    pipeline_item.association(:assignee).reset
    pipeline_item
  end

  private

  def same_pipeline?
    pipeline_item.pipeline_stage.pipeline_id == target_pipeline.id
  end

  def fetch_target_stage
    target_pipeline.pipeline_stages.find(target_stage_id)
  rescue ActiveRecord::RecordNotFound
    raise InvalidTargetStageError, I18n.t('errors.pipeline_item.invalid_target_stage')
  end

  def next_position(target_stage)
    (target_stage.pipeline_items.maximum(:position) || -1) + 1
  end

  def exportable_assignee_id(pipeline)
    return nil if pipeline_item.assignee_id.blank?
    return pipeline_item.assignee_id if pipeline_item.assignee&.administrator?
    return pipeline_item.assignee_id if pipeline.members.exists?(id: pipeline_item.assignee_id)

    nil
  end
end
