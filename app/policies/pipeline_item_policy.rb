class PipelineItemPolicy < ApplicationPolicy
  class Scope < ApplicationPolicy::Scope
    def resolve
      scope.all
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
    @account_user.administrator? || Current.user.assigned_pipelines.include?(record.pipeline)
  end

  def reorder?
    true
  end

  def export?
    true
  end
end
