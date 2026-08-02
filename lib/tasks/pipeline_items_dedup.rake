# Report and merge pipeline_item duplicates (same contact_id + pipeline_id), per the criteria
# in claude/pipeline_tasks/02-migracao-mesclagem-duplicados.md.
#
# Usage:
#   bundle exec rake pipeline_items:report_duplicates [ACCOUNT_ID=1]   # read-only
#   bundle exec rake pipeline_items:merge_duplicates [ACCOUNT_ID=1]    # destructive
# rubocop:disable Metrics/BlockLength
namespace :pipeline_items do
  desc 'Reports pipeline_item duplicates (same contact_id + pipeline_id) without changing data'
  task report_duplicates: :environment do
    groups = PipelineItems::DuplicateMerger.duplicate_groups(account_id: ENV.fetch('ACCOUNT_ID', nil))
    puts "#{groups.size} duplicate group(s) found."

    groups.each do |group|
      items = PipelineItem.where(id: group[:pipeline_item_ids]).includes(:pipeline_stage, :contact).order(:id).to_a
      winner = PipelineItems::DuplicateMerger.new(items).winner
      contact = items.first.contact
      pipeline = items.first.pipeline_stage.pipeline

      puts "\n== contact=##{contact.id} (#{contact.name}) pipeline=##{pipeline.id} (#{pipeline.name}) — #{items.size} card(s) =="
      items.each do |item|
        marker = item.id == winner.id ? '[VENCEDOR]' : '[perdedor]'
        puts "  #{marker} card=##{item.id} stage=#{item.pipeline_stage.name} stage_type=#{item.pipeline_stage.stage_type} " \
             "stage_position=#{item.pipeline_stage.position} value=#{item.value} notes_length=#{item.notes.to_s.length} " \
             "conversation_id=#{item.conversation_id || '-'} assignee_id=#{item.assignee_id || '-'} updated_at=#{item.updated_at}"
      end
    end

    puts "\nDRY RUN — nenhum dado foi alterado. Revise com o time/cliente antes de rodar pipeline_items:merge_duplicates."
  end

  desc 'Merges pipeline_item duplicates (same contact_id + pipeline_id). Destructive: destroys losing cards. Idempotent.'
  task merge_duplicates: :environment do
    groups = PipelineItems::DuplicateMerger.duplicate_groups(account_id: ENV.fetch('ACCOUNT_ID', nil))
    puts "#{groups.size} duplicate group(s) to merge."

    merged = 0
    errored = 0

    groups.each do |group|
      result = PipelineItems::DuplicateMerger.merge_group!(group[:pipeline_item_ids])

      if result
        message = "contact=##{group[:contact_id]} pipeline=##{group[:pipeline_id]} winner=##{result[:winner_id]} " \
                  "destroyed=#{result[:loser_ids].join(',')}"
        Rails.logger.info("[PipelineItems::DuplicateMerger] #{message}")
        puts "  merged: #{message}"
        merged += 1
      end
    rescue StandardError => e
      errored += 1
      message = "contact=##{group[:contact_id]} pipeline=##{group[:pipeline_id]}: #{e.message}"
      Rails.logger.error("[PipelineItems::DuplicateMerger] failed for #{message}")
      puts "  ERROR #{message}"
    end

    puts "\nDone. Merged: #{merged}, Errored: #{errored}, Total groups: #{groups.size}"
  end
end
# rubocop:enable Metrics/BlockLength
