class Api::V1::Accounts::PipelinesController < Api::V1::Accounts::BaseController
  before_action :fetch_pipeline, only: [:show, :update, :destroy]
  before_action :check_authorization

  def index
    @pipelines = policy_scope(Current.account.pipelines).includes(:pipeline_stages)
    @items_counts = items_counts_for(@pipelines.flat_map(&:pipeline_stages))
  end

  def show
    @items_counts = items_counts_for(@pipeline.pipeline_stages)
  end

  def create
    @pipeline = Current.account.pipelines.new(pipeline_params)
    @pipeline.save!
    @items_counts = {}
  end

  def update
    @pipeline.update!(pipeline_params)
    @items_counts = items_counts_for(@pipeline.pipeline_stages)
  end

  def destroy
    @pipeline.destroy!
    head :ok
  end

  private

  def fetch_pipeline
    @pipeline = policy_scope(Current.account.pipelines).includes(:pipeline_stages).find(params[:id])
  end

  def items_counts_for(stages)
    PipelineItem.where(pipeline_stage_id: Array(stages).map(&:id)).group(:pipeline_stage_id).count
  end

  def pipeline_params
    params.require(:pipeline).permit(:name, :description, :position, :enable_auto_assignment, :max_assignment_limit, :sync_assignments,
                                     :stale_alert_days)
  end
end
