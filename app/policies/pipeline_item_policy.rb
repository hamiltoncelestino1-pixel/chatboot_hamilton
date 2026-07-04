class PipelineItemPolicy < ApplicationPolicy
  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.all if @account_user.administrator?

      scope.where(assignee_id: [nil, @user.id])
    end
  end

  def index?
    true
  end

  def show?
    true
  end

  def create?
    true
  end

  def update?
    true
  end

  def destroy?
    @account_user.administrator?
  end

  def reorder?
    true
  end
end
