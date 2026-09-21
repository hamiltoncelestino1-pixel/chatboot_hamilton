class Api::V1::Accounts::PipelineStagesController < Api::V1::Accounts::BaseController
  before_action :fetch_pipeline
  before_action :fetch_stage, only: [:show, :update, :destroy]
  before_action :check_authorization

  def index
    @stages = @pipeline.pipeline_stages
    @items_counts = PipelineItem.where(pipeline_stage_id: @stages.map(&:id)).group(:pipeline_stage_id).count
  end

  def show
    @items_counts = { @stage.id => @stage.pipeline_items.count }
  end

  def create
    @stage = @pipeline.pipeline_stages.new(stage_params.merge(account: Current.account, stage_type: :normal))
    @stage.save!
    @items_counts = {}
  end

  def update
    @stage.update!(stage_params)
    @items_counts = { @stage.id => @stage.pipeline_items.count }
  end

  def destroy
    @stage.destroy!
    head :ok
  rescue ActiveRecord::RecordNotDestroyed => e
    render json: { error: e.record.errors[:base].first }, status: :unprocessable_entity
  end

  # POST /api/v1/accounts/:account_id/pipelines/:pipeline_id/pipeline_stages/reorder
  # Body: { ordered_ids: [3, 1, 2] }
  def reorder
    ordered_ids = params[:ordered_ids].map(&:to_i)
    stages_by_id = @pipeline.pipeline_stages.index_by(&:id)

    start_ids = ordered_ids.select { |id| stages_by_id[id]&.start? }
    normal_ids = ordered_ids.select { |id| stages_by_id[id]&.normal? }
    terminal_ids = ordered_ids.select { |id| stages_by_id[id]&.won? || stages_by_id[id]&.lost? }

    normalized = start_ids + normal_ids + terminal_ids

    normalized.each_with_index do |stage_id, index|
      stages_by_id[stage_id]&.update_column(:position, index)
    end
    head :ok
  end

  private

  def fetch_pipeline
    @pipeline = policy_scope(Current.account.pipelines).find(params[:pipeline_id])
  end

  def fetch_stage
    @stage = @pipeline.pipeline_stages.find(params[:id])
  end

  def stage_params
    params.require(:pipeline_stage).permit(:name, :color, :position)
  end
end
