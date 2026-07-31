module Enterprise::AutoAssignment::AssignmentService
  private

  # Override assignment config to use policy if available
  def assignment_config
    return super unless policy

    {
      'conversation_priority' => policy.conversation_priority,
      'fair_distribution_limit' => policy.fair_distribution_limit,
      'fair_distribution_window' => policy.fair_distribution_window,
      'balanced' => policy.balanced?
    }.compact
  end

  # Extend agent finding to add capacity checks
  def find_available_agent(conversation = nil)
    agents = filter_agents_by_team(inbox.available_agents, conversation)
    return nil if agents.nil?
    return nil if agents.empty?

    agents = apply_with_fallback(agents, 'rate_limit', conversation) { |scope| filter_agents_by_rate_limit(scope) }
    agents = apply_with_fallback(agents, 'capacity', conversation) { |scope| filter_agents_by_capacity(scope) } if capacity_filtering_enabled?

    selector = assignment_mode_balanced? ? balanced_selector : round_robin_selector
    selector.select_agent(agents)
  end

  # Nunca deixa uma conversa sem atribuição por causa de rate-limit/capacidade — só time
  # (filter_agents_by_team, acima) ou ausência total de membros são fronteiras rígidas. Se o
  # filtro esvaziar um conjunto que tinha candidatos antes dele, volta ao conjunto anterior e
  # loga bem alto — nunca silencioso.
  def apply_with_fallback(agents, filter_name, conversation)
    filtered = yield(agents)
    return filtered if filtered.present?

    Rails.logger.warn(
      "[AutoAssignment::Fallback] inbox_id=#{inbox.id} account_id=#{account.id} " \
      "conversation_id=#{conversation&.id} filter=#{filter_name} " \
      "eligible_before=#{agents.map(&:user_id)} " \
      'reason=all_agents_excluded_by_filter action=ignoring_filter_as_last_resort'
    )
    agents
  end

  # Prioridade: AssignmentPolicy vinculada > config direta na inbox (auto_assignment_config).
  # Mesmo no caminho direto (sem policy), respeita o feature flag — se um Super Admin
  # desabilitar advanced_assignment pontualmente numa conta no futuro, o balanceamento por
  # carga é desativado ali sem precisar mexer no jsonb de cada inbox individualmente.
  def assignment_mode_balanced?
    return false unless account.feature_enabled?('advanced_assignment')
    return true if policy&.balanced?

    inbox.auto_assignment_config['assignment_mode'] == 'balanced'
  end

  def filter_agents_by_capacity(agents)
    return agents unless capacity_filtering_enabled?

    capacity_service = Enterprise::AutoAssignment::CapacityService.new
    agents.select { |agent_member| capacity_service.agent_has_capacity?(agent_member.user, inbox) }
  end

  def capacity_filtering_enabled?
    account.feature_enabled?('advanced_assignment') &&
      account.account_users.joins(:agent_capacity_policy).exists?
  end

  def round_robin_selector
    @round_robin_selector ||= AutoAssignment::RoundRobinSelector.new(inbox: inbox)
  end

  def balanced_selector
    @balanced_selector ||= Enterprise::AutoAssignment::BalancedSelector.new(inbox: inbox)
  end

  def policy
    @policy ||= inbox.assignment_policy
  end

  def account
    inbox.account
  end

  # Override to apply exclusion rules
  def unassigned_conversations(limit)
    scope = inbox.conversations.unassigned.open

    # Apply exclusion rules from capacity policy or assignment policy
    scope = apply_exclusion_rules(scope)

    # Apply conversation priority using enum methods if policy exists
    scope = if policy&.longest_waiting?
              scope.reorder(last_activity_at: :asc, created_at: :asc)
            else
              scope.reorder(created_at: :asc)
            end

    scope.limit(limit)
  end

  def apply_exclusion_rules(scope)
    capacity_policy = inbox.inbox_capacity_limits.first&.agent_capacity_policy
    return scope unless capacity_policy

    exclusion_rules = capacity_policy.exclusion_rules || {}
    scope = apply_label_exclusions(scope, exclusion_rules['excluded_labels'])
    apply_age_exclusions(scope, exclusion_rules['exclude_older_than_hours'])
  end

  def apply_label_exclusions(scope, excluded_labels)
    return scope if excluded_labels.blank?

    scope.tagged_with(excluded_labels, exclude: true, on: :labels)
  end

  def apply_age_exclusions(scope, hours_threshold)
    return scope if hours_threshold.blank?

    hours = hours_threshold.to_i
    return scope unless hours.positive?

    scope.where('conversations.created_at >= ?', hours.hours.ago)
  end
end
