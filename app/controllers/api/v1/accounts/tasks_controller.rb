class Api::V1::Accounts::TasksController < Api::V1::Accounts::BaseController
  before_action :fetch_task, only: [:show, :update, :destroy, :complete]
  before_action :check_authorization

  def index
    items = policy_scope(Current.account.tasks.includes(:assignee))
    items = items.where(contact_id: params[:contact_id]) if params[:contact_id].present?
    items = items.where(conversation_id: params[:conversation_id]) if params[:conversation_id].present?
    items = items.where(pipeline_item_id: params[:pipeline_item_id]) if params[:pipeline_item_id].present?
    @tasks = items.order(due_date: :asc)
  end

  def show; end

  def create
    @task = Current.account.tasks.new(create_params)
    @task.assignee_id ||= Current.user.id
    @task.save!
  end

  def update
    @task.update!(update_params)
  end

  # PATCH /api/v1/accounts/:account_id/tasks/:id/complete
  def complete
    @task.update!(completed_at: Time.zone.now)
    render :show
  end

  def destroy
    @task.destroy!
    head :ok
  end

  private

  def check_authorization
    authorize(@task || Task)
  end

  def fetch_task
    @task = policy_scope(Current.account.tasks).find(params[:id])
  end

  def create_params
    params.require(:task).permit(:title, :due_date, :contact_id, :conversation_id, :pipeline_item_id, :assignee_id,
                                 :recurrence_interval)
  end

  def update_params
    params.require(:task).permit(:title, :due_date, :assignee_id, :recurrence_interval)
  end
end
