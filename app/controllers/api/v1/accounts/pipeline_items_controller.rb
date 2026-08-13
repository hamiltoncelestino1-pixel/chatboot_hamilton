class Api::V1::Accounts::PipelineItemsController < Api::V1::Accounts::BaseController
  before_action :fetch_item, only: [:show, :update, :destroy, :export]
  before_action :check_authorization

  rescue_from Pipelines::ExportItemService::SamePipelineError,
              Pipelines::ExportItemService::InvalidTargetStageError do |e|
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def index
    return nested_pipeline_index if params[:pipeline_id].present?

    items = policy_scope(
      Current.account.pipeline_items
             .joins(:pipeline_stage)
             .where(pipeline_stages: { pipeline_id: policy_scope(Current.account.pipelines).select(:id) })
             .includes(:contact, :conversation, :assignee, :team, pipeline_stage: :pipeline)
    )
    items = items.where(contact_id: params[:contact_id]) if params[:contact_id].present?
    items = items.where(conversation_id: params[:conversation_id]) if params[:conversation_id].present?
    @items = items.order(created_at: :desc)
  end

  def show; end

  def create
    allowed_pipeline_ids = policy_scope(Current.account.pipelines).select(:id)
    Current.account.pipeline_stages
           .where(pipeline_id: allowed_pipeline_ids)
           .find(create_params[:pipeline_stage_id])
    @item = Current.account.pipeline_items.new(create_params)
    @item.save!
    Pipelines::AutoAssignmentService.new(pipeline_item: @item).perform
  end

  def update
    @item.update!(update_params)
    @item.association(:assignee).reset if update_params.key?(:assignee_id)
    @item.association(:team).reset if update_params.key?(:team_id)
    @item.association(:pipeline_stage).reset if update_params.key?(:pipeline_stage_id)
  end

  def destroy
    @item.destroy!
    head :ok
  end

  # POST /api/v1/accounts/:account_id/pipeline_items/:id/export
  # Body: { pipeline_item: { target_pipeline_id: 3, target_stage_id: 12 } }
  def export
    target_pipeline = policy_scope(Current.account.pipelines).find(export_params[:target_pipeline_id])
    @item = Pipelines::ExportItemService.new(
      pipeline_item: @item,
      target_pipeline: target_pipeline,
      target_stage_id: export_params[:target_stage_id]
    ).perform
    render :show
  end

  # POST /api/v1/accounts/:account_id/pipeline_items/reorder
  # Body: { stage_id: 1, ordered_ids: [5, 2, 8] }
  def reorder
    allowed_pipeline_ids = policy_scope(Current.account.pipelines).select(:id)
    stage = Current.account.pipeline_stages
                   .joins(:pipeline)
                   .where(pipeline_id: allowed_pipeline_ids)
                   .find(params[:stage_id])
    visible_item_ids = policy_scope(stage.pipeline_items).pluck(:id)
    params[:ordered_ids].each_with_index do |item_id, index|
      next unless visible_item_ids.include?(item_id.to_i)

      stage.pipeline_items.find(item_id).update_column(:position, index)
    end
    head :ok
  end

  private

  def check_authorization
    authorize(@item || PipelineItem)
  end

  def nested_pipeline_index
    @pipeline = policy_scope(Current.account.pipelines).find(params[:pipeline_id])
    @items = pipeline_items_scope
    @items = @items.where(pipeline_stage_id: params[:stage_id]) if params[:stage_id].present?
    render :index
  end

  def fetch_item
    allowed_pipeline_ids = policy_scope(Current.account.pipelines).select(:id)
    @item = policy_scope(
      Current.account.pipeline_items
             .joins(:pipeline_stage)
             .where(pipeline_stages: { pipeline_id: allowed_pipeline_ids })
             .includes(:contact, :assignee, :team, pipeline_stage: :pipeline)
    ).find(params[:id])
  end

  def pipeline_items_scope
    policy_scope(
      @pipeline.pipeline_items
               .includes(:contact, :conversation, :assignee, :team, pipeline_stage: :pipeline)
    ).order('pipeline_stage_id, position')
  end

  def create_params
    params.require(:pipeline_item).permit(
      :pipeline_stage_id, :contact_id, :conversation_id,
      :title, :value, :notes, :position, :assignee_id, :team_id,
      custom_attributes: {}
    )
  end

  def update_params
    params.require(:pipeline_item).permit(
      :pipeline_stage_id, :conversation_id,
      :title, :value, :notes, :position, :assignee_id, :team_id,
      custom_attributes: {}
    )
  end

  def export_params
    params.require(:pipeline_item).permit(:target_pipeline_id, :target_stage_id)
  end
end
