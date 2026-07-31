module Enterprise::Inbox
  ASSIGNMENT_MODES = %w[round_robin balanced].freeze

  def member_ids_with_assignment_capacity
    return super unless enable_auto_assignment?
    return member_ids_with_capacity_fallback if auto_assignment_v2_enabled?

    max_assignment_limit = auto_assignment_config['max_assignment_limit']
    overloaded_agent_ids = max_assignment_limit.present? ? get_agent_ids_over_assignment_limit(max_assignment_limit) : []
    eligible = super
    with_capacity = eligible - overloaded_agent_ids
    return with_capacity if with_capacity.present? || eligible.blank?

    Rails.logger.warn(
      "[AutoAssignment::Fallback] inbox_id=#{id} account_id=#{account_id} " \
      "filter=max_assignment_limit eligible_before=#{eligible} " \
      'reason=all_agents_over_limit action=ignoring_limit_as_last_resort'
    )
    eligible
  end

  def active_bot?
    super || captain_active?
  end

  def captain_active?
    captain_assistant.present? && more_responses?
  end

  private

  def more_responses?
    account.usage_limits[:captain][:responses][:current_available].positive?
  end

  # V2 capacity path (agent_capacity_policy). This is the only entry point for
  # member_ids_with_assignment_capacity's v2 branch — a module prepended directly onto a class
  # (Inbox.prepend_mod_with('Inbox') => Enterprise::Inbox, this module) always wins method
  # resolution over a module only reached via `include` (InboxAgentAvailability), even if that
  # included module has its own prepend on it. `filter_by_capacity` and friends still live in
  # Enterprise::InboxAgentAvailability and are called from here, just not its entry point.
  def member_ids_with_capacity_fallback
    eligible = available_agents
    with_capacity = filter_by_capacity(eligible)
    return with_capacity.map(&:user_id) if with_capacity.present? || eligible.blank?

    Rails.logger.warn(
      "[AutoAssignment::Fallback] inbox_id=#{id} account_id=#{account_id} " \
      "filter=agent_capacity_policy eligible_before=#{eligible.map(&:user_id)} " \
      'reason=all_agents_over_capacity action=ignoring_limit_as_last_resort'
    )
    eligible.map(&:user_id)
  end

  def get_agent_ids_over_assignment_limit(limit)
    conversations
      .open
      .where(account_id: account_id)
      .select(:assignee_id)
      .group(:assignee_id)
      .having("count(*) >= #{limit.to_i}")
      .filter_map(&:assignee_id)
  end

  def ensure_valid_max_assignment_limit
    return if auto_assignment_config['max_assignment_limit'].blank?
    return if auto_assignment_config['max_assignment_limit'].to_i.positive?

    errors.add(:auto_assignment_config, 'max_assignment_limit must be greater than 0')
  end

  def ensure_valid_assignment_mode
    mode = auto_assignment_config['assignment_mode']
    return if mode.blank?
    return if ASSIGNMENT_MODES.include?(mode)

    errors.add(:auto_assignment_config, "assignment_mode must be one of #{ASSIGNMENT_MODES.join(', ')}")
  end
end
