class Conversations::PermissionFilterService
  attr_reader :conversations, :user, :account

  def initialize(conversations, user, account)
    @conversations = conversations
    @user = user
    @account = account
  end

  def perform
    return conversations if user_role == 'administrator'

    accessible_conversations
  end

  private

  def accessible_conversations
    if account.enforce_team_based_access
      team_scoped_conversations
    else
      conversations.where(inbox: user.inboxes.where(account_id: account.id))
    end
  end

  def team_scoped_conversations
    team_ids = user.teams.where(account_id: account.id).pluck(:id)
    conversations.where(team_id: team_ids)
  end

  def account_user
    AccountUser.find_by(account_id: account.id, user_id: user.id)
  end

  def user_role
    account_user&.role
  end
end

Conversations::PermissionFilterService.prepend_mod_with('Conversations::PermissionFilterService')
