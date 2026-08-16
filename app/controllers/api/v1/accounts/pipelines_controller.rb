class Api::V1::Accounts::PipelinesController < Api::V1::Accounts::BaseController
  before_action :fetch_pipeline, only: [:show, :update, :destroy]
  before_action :check_authorization

  def index
    @pipelines = policy_scope(Current.account.pipelines).includes(pipeline_stages: :pipeline_items)
  end

  def show; end

  def create
    @pipeline = Current.account.pipelines.new(pipeline_params)
    @pipeline.save!
  end

  def update
    @pipeline.update!(pipeline_params)
  end

  def destroy
    @pipeline.destroy!
    head :ok
  end

  private

  def fetch_pipeline
    @pipeline = policy_scope(Current.account.pipelines).includes(pipeline_stages: :pipeline_items).find(params[:id])
  end

  def pipeline_params
    params.require(:pipeline).permit(:name, :description, :position, :enable_auto_assignment, :max_assignment_limit, :sync_assignments)
  end
end
