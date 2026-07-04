class PipelinePolicy < ApplicationPolicy
  class Scope < ApplicationPolicy::Scope
    def resolve
      user.assigned_pipelines
    end
  end

  def index?
    true
  end

  def show?
    Current.user.assigned_pipelines.include?(record)
  end

  def create?
    @account_user.administrator?
  end

  def update?
    @account_user.administrator?
  end

  def destroy?
    @account_user.administrator?
  end
end
