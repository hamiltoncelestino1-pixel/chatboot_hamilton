# frozen_string_literal: true

# Ferramentas de auditoria/reparo para conversas com referências órfãs
# (contact_inbox_id / contact_id apontando para registros que não existem mais).
#
# Contexto: encontrado em produção que Conversation#contact_inbox_id pode ficar
# órfão (ex.: conversation_id=384 apontava para um ContactInbox já deletado),
# quebrando a serialização em Message#conversation_push_event_data. O código já
# foi corrigido para tolerar isso (contact_inbox nil vira `nil` no payload em vez
# de estourar exceção) — estas tasks servem para mapear e, quando seguro, corrigir
# o dado em si.
namespace :data_integrity do
  desc 'Lista conversas com contact_inbox_id e/ou contact_id órfãos (apontando para registros inexistentes)'
  task audit_orphaned_conversations: :environment do
    orphaned_contact_inbox = Conversation
                             .where.not(contact_inbox_id: nil)
                             .where.not(contact_inbox_id: ContactInbox.select(:id))

    orphaned_contact = Conversation
                       .where.not(contact_id: nil)
                       .where.not(contact_id: Contact.select(:id))

    puts "== Conversas com contact_inbox_id órfão (#{orphaned_contact_inbox.count}) =="
    orphaned_contact_inbox.find_each do |c|
      contact_ok = c.contact_id.present? && Contact.exists?(c.contact_id)
      puts "conversation_id=#{c.id} display_id=#{c.display_id} account_id=#{c.account_id} " \
           "inbox_id=#{c.inbox_id} assignee_id=#{c.assignee_id} " \
           "contact_inbox_id(órfão)=#{c.contact_inbox_id} contact_id=#{c.contact_id} contact_existe=#{contact_ok}"
    end

    puts "\n== Conversas com contact_id órfão (#{orphaned_contact.count}) =="
    orphaned_contact.find_each do |c|
      puts "conversation_id=#{c.id} display_id=#{c.display_id} account_id=#{c.account_id} " \
           "inbox_id=#{c.inbox_id} assignee_id=#{c.assignee_id} contact_id(órfão)=#{c.contact_id}"
    end

    puts "\nTotal geral: #{(orphaned_contact_inbox.pluck(:id) | orphaned_contact.pluck(:id)).size} conversa(s) únicas afetadas."
  end

  desc 'Repara contact_inbox_id órfão reaproveitando um ContactInbox existente do mesmo contact_id+inbox_id, ' \
       'quando existir. Não mexe em contact_id. Dry-run por padrão — rode com DRY_RUN=false para aplicar.'
  task fix_orphaned_contact_inboxes: :environment do
    dry_run = ActiveModel::Type::Boolean.new.cast(ENV.fetch('DRY_RUN', true))

    orphaned = Conversation
              .where.not(contact_inbox_id: nil)
              .where.not(contact_inbox_id: ContactInbox.select(:id))

    puts "#{orphaned.count} conversa(s) com contact_inbox_id órfão encontrada(s)."
    fixed = 0
    needs_review = 0

    orphaned.find_each do |conversation|
      replacement = ContactInbox.find_by(contact_id: conversation.contact_id, inbox_id: conversation.inbox_id)

      if replacement
        puts "conversation_id=#{conversation.id}: contact_inbox_id #{conversation.contact_inbox_id} (órfão) " \
             "-> #{replacement.id} (ContactInbox existente reaproveitado)"
        conversation.update_column(:contact_inbox_id, replacement.id) unless dry_run
        fixed += 1
      else
        puts "conversation_id=#{conversation.id}: SEM substituto (contact_id=#{conversation.contact_id}, " \
             "inbox_id=#{conversation.inbox_id}) — precisa revisão manual, não alterado"
        needs_review += 1
      end
    end

    puts "\n#{fixed} corrigida(s) automaticamente, #{needs_review} precisam de revisão manual."
    puts dry_run ? 'DRY RUN — nada foi alterado. Rode com DRY_RUN=false para aplicar de fato.' : 'Concluído.'
  end
end
