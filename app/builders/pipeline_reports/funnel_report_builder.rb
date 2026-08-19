class PipelineReports::FunnelReportBuilder
  pattr_initialize [:account!, :pipeline!]

  # NOTE: this is a snapshot approximation, not a full historical funnel:
  # - stage_distribution counts cards currently in each stage, not conversion rates over time.
  # - avg_time_in_stage averages stage_changed_at only for cards still sitting in that stage
  #   today, not every card that ever passed through it (there's no stage-change history
  #   table - see claude/crm_features_tasks/04-backend-relatorio-funil.md for the full note).
  def build
    {
      open_value: open_value,
      stage_distribution: stage_distribution,
      avg_time_in_stage: avg_time_in_stage
    }
  end

  private

  def open_items
    # reorder(nil): Pipeline#pipeline_items is has_many :through PipelineStage, which
    # defines its own has_many :pipeline_items, -> { order(:position) } - that implicit
    # ORDER BY pipeline_items.position breaks the GROUP BY queries below in Postgres.
    @open_items ||= pipeline.pipeline_items.joins(:pipeline_stage)
                            .where.not(pipeline_stages: { stage_type: %i[won lost] })
                            .reorder(nil)
  end

  def open_value
    open_items.sum(:value).to_f
  end

  def stage_distribution
    open_items.group('pipeline_stages.name').count
  end

  def avg_time_in_stage
    open_items.group('pipeline_stages.name')
              .average(Arel.sql('EXTRACT(EPOCH FROM (now() - stage_changed_at))'))
              .transform_values(&:to_f)
  end
end
