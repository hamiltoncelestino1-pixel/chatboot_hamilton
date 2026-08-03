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
    if params[:pipeline_item_ids].present?
      ::MacrosPipelineExecutionJob.perform_later(@macro, pipeline_item_ids: authorized_pipeline_item_ids, user: Current.user)
    else
      ::MacrosExecutionJob.perform_later(@macro, conversation_ids: params[:conversation_ids], user: Current.user)
    end

    head :ok
  end

  private

  # PipelineItemPolicy::Scope is unconditional (scope.all) - the actual per-pipeline
  # restriction lives in PipelinePolicy::Scope (assigned_pipelines), so authorization must
  # go through the pipeline, mirroring PipelineItemsController#fetch_item/#index.
  def authorized_pipeline_item_ids
    allowed_pipeline_ids = policy_scope(Current.account.pipelines).select(:id)
    Current.account.pipeline_items
           .joins(:pipeline_stage)
           .where(pipeline_stages: { pipeline_id: allowed_pipeline_ids })
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
