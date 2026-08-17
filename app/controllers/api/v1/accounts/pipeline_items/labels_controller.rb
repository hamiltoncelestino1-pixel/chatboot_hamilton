class Api::V1::Accounts::PipelineItems::LabelsController < Api::V1::Accounts::BaseController
  include LabelConcern
  before_action :fetch_item

  private

  def check_authorization
    authorize @item, :update?
  end

  def fetch_item
    allowed_pipeline_ids = policy_scope(Current.account.pipelines).select(:id)
    @item = Current.account.pipeline_items
                   .where(pipeline_id: allowed_pipeline_ids)
                   .find(params[:pipeline_item_id])
    check_authorization
  end

  def model
    @model ||= @item
  end

  def permitted_params
    params.permit(:pipeline_item_id, labels: [])
  end
end
