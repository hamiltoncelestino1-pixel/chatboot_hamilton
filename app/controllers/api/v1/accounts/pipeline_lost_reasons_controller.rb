class Api::V1::Accounts::PipelineLostReasonsController < Api::V1::Accounts::BaseController
  before_action :fetch_reason, only: [:update, :destroy]
  before_action :check_authorization

  def index
    @reasons = policy_scope(Current.account.pipeline_lost_reasons).order(:title)
  end

  def create
    @reason = Current.account.pipeline_lost_reasons.new(reason_params)
    @reason.save!
  end

  def update
    @reason.update!(reason_params)
  end

  def destroy
    @reason.destroy!
    head :ok
  end

  private

  def fetch_reason
    @reason = policy_scope(Current.account.pipeline_lost_reasons).find(params[:id])
  end

  def reason_params
    params.require(:pipeline_lost_reason).permit(:title)
  end
end
