class Api::V1::Accounts::PipelineMembersController < Api::V1::Accounts::BaseController
  before_action :fetch_pipeline
  before_action :check_authorization
  before_action :validate_member_id_params, only: [:create, :update, :destroy]

  def index
    @pipeline_members = @pipeline.members
  end

  def create
    ActiveRecord::Base.transaction do
      @pipeline_members = @pipeline.add_members(members_to_be_added_ids)
    end
  end

  def update
    ActiveRecord::Base.transaction do
      @pipeline.add_members(members_to_be_added_ids)
      @pipeline.remove_members(members_to_be_removed_ids)
    end
    @pipeline_members = @pipeline.members
    render action: 'create'
  end

  def destroy
    ActiveRecord::Base.transaction do
      @pipeline.remove_members(params[:user_ids])
    end
    head :ok
  end

  private

  def members_to_be_added_ids
    params[:user_ids] - current_members_ids
  end

  def members_to_be_removed_ids
    current_members_ids - params[:user_ids]
  end

  def current_members_ids
    @current_members_ids ||= @pipeline.members.pluck(:id)
  end

  def fetch_pipeline
    @pipeline = policy_scope(Current.account.pipelines).find(params[:pipeline_id])
  end

  def validate_member_id_params
    invalid_ids = params[:user_ids].map(&:to_i) - @pipeline.account.user_ids
    render json: { error: 'Invalid User IDs' }, status: :unauthorized and return if invalid_ids.present?
  end
end
