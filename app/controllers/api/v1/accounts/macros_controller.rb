class Api::V1::Accounts::MacrosController < Api::V1::Accounts::BaseController
  include AttachmentConcern
  include PermittedActionParams

  before_action :fetch_macro, only: [:show, :update, :destroy, :execute]
  before_action :check_authorization, only: [:show, :update, :destroy, :execute]

  def index
    @macros = Macro.with_visibility(current_user, params)
  end

  def show
    head :not_found if @macro.nil?
  end

  def create
    blobs, actions, error = validate_and_prepare_attachments(permitted_actions(params[:actions]))
    return render_could_not_create_error(error) if error

    @macro = Current.account.macros.new(macros_with_user.merge(created_by_id: current_user.id))
    @macro.set_visibility(current_user, permitted_params)
    @macro.actions = actions

    return render_could_not_create_error(@macro.errors.messages) unless @macro.valid?

    @macro.save!
    blobs.each { |blob| @macro.files.attach(blob) }
  end

  def update
    blobs, actions, error = validate_and_prepare_attachments(permitted_actions(params[:actions]), @macro)
    return render_could_not_create_error(error) if error

    ActiveRecord::Base.transaction do
      @macro.assign_attributes(macros_with_user)
      @macro.set_visibility(current_user, permitted_params)
      @macro.actions = actions if params[:actions]
      @macro.save!
      blobs.each { |blob| @macro.files.attach(blob) }
    rescue StandardError => e
      Rails.logger.error e
      render_could_not_create_error(@macro.errors.messages)
    end
  end

  def destroy
    @macro.destroy!
    head :ok
  end

  def execute
    case @macro.macro_type
    when 'pipeline_item'
      execute_pipeline_item_macro
    else
      execute_conversation_macro
    end
  end

  private

  def execute_conversation_macro
    return render_could_not_create_error(I18n.t('errors.macros.execute.conversation_ids_required')) if params[:conversation_ids].blank?

    ::MacrosExecutionJob.perform_later(@macro, conversation_ids: params[:conversation_ids], user: Current.user)
    head :ok
  end

  # Two ways to target pipeline items: an explicit list (single card, from KanbanCard), or a
  # stage_id + the board's active filters, to run on every card currently matching that column -
  # not just the page the frontend happened to have loaded (task 07: pagination silently broke
  # the old "pass every loaded id" approach, running on 25 cards when the agent meant 900). The
  # job resolves the stage_id case against the live data at execution time, same filters applied
  # server-side via PipelineItemFinder.
  def execute_pipeline_item_macro
    if params[:stage_id].present?
      execute_pipeline_item_macro_for_stage
    elsif params[:pipeline_item_ids].present?
      ::MacrosPipelineExecutionJob.perform_later(@macro, pipeline_item_ids: authorized_pipeline_item_ids, user: Current.user)
      head :ok
    else
      render_could_not_create_error(I18n.t('errors.macros.execute.pipeline_item_ids_required'))
    end
  end

  def execute_pipeline_item_macro_for_stage
    stage = authorized_pipeline_stage
    return render_could_not_create_error(I18n.t('errors.macros.execute.stage_not_found')) if stage.blank?

    ::MacrosPipelineExecutionJob.perform_later(
      @macro, stage_id: stage.id, filters: pipeline_item_filter_params, user: Current.user
    )
    head :ok
  end

  def authorized_pipeline_stage
    allowed_pipeline_ids = policy_scope(Current.account.pipelines).select(:id)
    Current.account.pipeline_stages.joins(:pipeline).where(pipeline_id: allowed_pipeline_ids).find_by(id: params[:stage_id])
  end

  def pipeline_item_filter_params
    params.permit(
      :only_mine, :assignee_id, :created_at_from, :created_at_to,
      :updated_at_from, :updated_at_to, :value_min, :value_max,
      label_titles: []
    ).to_h
  end

  # PipelineItemPolicy::Scope is unconditional (scope.all) - the actual per-pipeline
  # restriction lives in PipelinePolicy::Scope (assigned_pipelines), so authorization must
  # go through the pipeline, mirroring PipelineItemsController#fetch_item/#index.
  def authorized_pipeline_item_ids
    allowed_pipeline_ids = policy_scope(Current.account.pipelines).select(:id)
    Current.account.pipeline_items
           .where(pipeline_id: allowed_pipeline_ids)
           .where(id: params[:pipeline_item_ids])
           .pluck(:id)
  end

  def permitted_params
    params.permit(:name, :visibility, :macro_type)
  end

  def macros_with_user
    permitted_params.merge(updated_by_id: current_user.id)
  end

  def fetch_macro
    @macro = Current.account.macros.find_by(id: params[:id])
  end

  def check_authorization
    authorize(@macro) if @macro.present?
  end
end
