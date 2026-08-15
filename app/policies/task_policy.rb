class TaskPolicy < ApplicationPolicy
  class Scope < ApplicationPolicy::Scope
    def resolve
      scope.all
    end
  end

  def index? = true
  def show? = true
  def create? = true
  def update? = true
  def complete? = true

  def destroy?
    @account_user.administrator? || record.assignee_id == Current.user.id
  end
end
