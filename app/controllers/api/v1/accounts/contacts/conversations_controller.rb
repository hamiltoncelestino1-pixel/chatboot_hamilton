class Api::V1::Accounts::Contacts::ConversationsController < Api::V1::Accounts::Contacts::BaseController
  def index
    # Start with all conversations for this contact
    conversations = Current.account.conversations.includes(
      :assignee, :contact, :inbox, :taggings
    ).where(contact_id: @contact.id)

    # Apply permission-based filtering using the existing service
    conversations = Conversations::PermissionFilterService.new(
      conversations,
      Current.user,
      Current.account
    ).perform

    @conversations = conversations.order(last_activity_at: :desc).limit(20)
  rescue StandardError => e
    # [DEBUG TEMPORÁRIO] Remover após diagnóstico do 500
    Rails.logger.error "[DEBUG] ContactConversations#index falhou para contact_id=#{params[:contact_id]}: #{e.class}: #{e.message}"
    Rails.logger.error e.backtrace.first(10).join("\n")
    render json: {
      debug: true,
      error: e.class.to_s,
      message: e.message,
      backtrace: e.backtrace.first(5)
    }, status: :internal_server_error
  end
end
