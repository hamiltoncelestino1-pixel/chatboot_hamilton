module Enterprise::InboxAgentAvailability
  extend ActiveSupport::Concern

  # No member_ids_with_assignment_capacity entry point here on purpose: this module is
  # reached via `Inbox`'s `include InboxAgentAvailability`, but `Inbox.prepend_mod_with('Inbox')`
  # prepends Enterprise::Inbox directly onto the Inbox class, which always wins method
  # resolution over anything reached only through an included module — even one that has
  # its own module prepended onto it, like this one. So Enterprise::Inbox#member_ids_with_assignment_capacity
  # (enterprise/app/models/enterprise/inbox.rb) is the real, only entry point for the v2
  # capacity path; the methods below are still used from there.
  private

  def filter_by_capacity(inbox_members_scope)
    return inbox_members_scope unless capacity_filtering_enabled?

    inbox_members_scope.select do |inbox_member|
      capacity_service.agent_has_capacity?(inbox_member.user, self)
    end
  end

  def capacity_filtering_enabled?
    account.feature_enabled?('advanced_assignment') &&
      account.account_users.joins(:agent_capacity_policy).exists?
  end

  def capacity_service
    @capacity_service ||= Enterprise::AutoAssignment::CapacityService.new
  end
end
