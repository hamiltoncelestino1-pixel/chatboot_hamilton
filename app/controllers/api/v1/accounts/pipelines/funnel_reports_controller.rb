class Api::V1::Accounts::Pipelines::FunnelReportsController < Api::V1::Accounts::BaseController
  before_action :check_authorization

  def show
    @pipeline = policy_scope(Current.account.pipelines).find(params[:pipeline_id])
    render json: PipelineReports::FunnelReportBuilder.new(account: Current.account, pipeline: @pipeline).build
  end

  private

  def check_authorization
    authorize :report, :view?
  end
end
