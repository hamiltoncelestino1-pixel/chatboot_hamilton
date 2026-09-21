class Api::V1::Accounts::PipelineItemsController < Api::V1::Accounts::BaseController
  before_action :fetch_item, only: [:show, :update, :destroy, :export]
  before_action :check_authorization

  rescue_from Pipelines::ExportItemService::SamePipelineError,
              Pipelines::ExportItemService::InvalidTargetStageError do |e|
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def index
    return nested_pipeline_index if params[:pipeline_id].present?

    @items = flat_pipeline_items_scope.order(created_at: :desc)
    @overdue_tasks_counts = overdue_tasks_counts_for(@items)
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
    @item.association(:pipeline_lost_reason).reset if update_params.key?(:pipeline_lost_reason_id)
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
  # Body: { stage_id: 1, ordered_ids: [5, 2, 8], start_position: 25 }
  # start_position is the offset of the page being reordered (0 for the first page) - without
  # it, reindexing from 0 every time would collide with the positions of cards on pages the
  # frontend hasn't loaded (claude/pipeline_performance_tasks/03-*.md, risk 5).
  def reorder
    allowed_pipeline_ids = policy_scope(Current.account.pipelines).select(:id)
    stage = Current.account.pipeline_stages
                   .joins(:pipeline)
                   .where(pipeline_id: allowed_pipeline_ids)
                   .find(params[:stage_id])
    reposition_items(stage, params[:start_position].to_i)
    head :ok
  end

  private

  def reposition_items(stage, start_position)
    items_by_id = stage.pipeline_items.index_by(&:id)
    visible_item_ids = policy_scope(stage.pipeline_items).pluck(:id)

    params[:ordered_ids].each_with_index do |item_id, index|
      id = item_id.to_i
      next unless visible_item_ids.include?(id)

      items_by_id[id]&.update_column(:position, start_position + index)
    end
  end

  def check_authorization
    authorize(@item || PipelineItem)
  end

  def nested_pipeline_index
    @pipeline = policy_scope(Current.account.pipelines).find(params[:pipeline_id])
    return render_board_index if params[:stage_id].present?

    @items = pipeline_items_scope
    @overdue_tasks_counts = overdue_tasks_counts_for(@items)
    render :index
  end

  # Paginated, filtered, sorted board column - the contract the Kanban board uses once the
  # frontend switches to per-column fetching (task 05/06). Only reachable with stage_id, so the
  # legacy unpaginated `index` (still used by ContactOpportunities/ConversationOpportunities and,
  # until task 06, the board's initial full-pipeline fetch) is untouched.
  def render_board_index
    finder = PipelineItemFinder.new(
      scope: policy_scope(@pipeline.pipeline_items).includes(pipeline_item_includes),
      stage_id: params[:stage_id], current_user: Current.user, params: params
    )
    @items = finder.perform
    @items_count = @items.total_count
    @current_page = finder.current_page
    @overdue_tasks_counts = overdue_tasks_counts_for(@items)
    render :board_index
  end

  def overdue_tasks_counts_for(items)
    Task.pending
        .where(pipeline_item_id: items.map(&:id))
        .where('due_date < ?', Time.current)
        .group(:pipeline_item_id).count
  end

  def flat_pipeline_items_scope
    items = policy_scope(
      Current.account.pipeline_items
             .where(pipeline_id: policy_scope(Current.account.pipelines).select(:id))
             .includes(pipeline_item_includes)
    )
    items = items.where(contact_id: params[:contact_id]) if params[:contact_id].present?
    items = items.where(conversation_id: params[:conversation_id]) if params[:conversation_id].present?
    items
  end

  def fetch_item
    allowed_pipeline_ids = policy_scope(Current.account.pipelines).select(:id)
    @item = policy_scope(
      Current.account.pipeline_items
             .where(pipeline_id: allowed_pipeline_ids)
             .includes(pipeline_item_includes)
    ).find(params[:id])
  end

  def pipeline_items_scope
    policy_scope(
      @pipeline.pipeline_items.includes(pipeline_item_includes)
    ).order('pipeline_stage_id, position')
  end

  # contact/assignee avatars and labels are read via preloaded associations (Avatarable#avatar_url
  # respects eager-loaded attachments; PipelineItem#preloaded_label_list reads preloaded taggings
  # because acts_as_taggable_on's #label_list always re-queries) - without this every card in a
  # listing fires its own avatar/label queries.
  def pipeline_item_includes
    [
      :conversation, :team, :pipeline_lost_reason,
      { contact: { avatar_attachment: :blob }, assignee: { avatar_attachment: :blob }, pipeline_stage: :pipeline, taggings: :tag }
    ]
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
      :title, :value, :notes, :position, :assignee_id, :team_id, :pipeline_lost_reason_id,
      custom_attributes: {}
    )
  end

  def export_params
    params.require(:pipeline_item).permit(:target_pipeline_id, :target_stage_id)
  end
end
