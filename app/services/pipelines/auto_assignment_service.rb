class Pipelines::AutoAssignmentService
  pattr_initialize [:pipeline_item!]

  def perform
    return if pipeline_item.assignee_id.present?
    return unless pipeline.enable_auto_assignment?

    agent = next_eligible_agent
    pipeline_item.update(assignee_id: agent.id) if agent
  end

  private

  def pipeline
    @pipeline ||= pipeline_item.pipeline_stage.pipeline
  end

  def next_eligible_agent
    members = pipeline.pipeline_members.order(:created_at).includes(:user).map(&:user).compact
    return nil if members.empty?

    counts = open_items_count_by_agent
    eligible = members.reject do |member|
      pipeline.max_assignment_limit.positive? &&
        counts[member.id].to_i >= pipeline.max_assignment_limit
    end

    eligible.min_by { |member| counts[member.id].to_i }
  end

  def open_items_count_by_agent
    terminal_types = [PipelineStage.stage_types[:won], PipelineStage.stage_types[:lost]]
    PipelineItem
      .joins(:pipeline_stage)
      .where(pipeline_stages: { pipeline_id: pipeline.id })
      .where.not(pipeline_stages: { stage_type: terminal_types })
      .where.not(assignee_id: nil)
      .group(:assignee_id)
      .count
  end
end
