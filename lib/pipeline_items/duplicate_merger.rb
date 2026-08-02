# Merges pipeline_items that duplicate the same (pipeline_id, contact_id) pair, per the
# criteria confirmed in claude/pipeline_tasks/02-migracao-mesclagem-duplicados.md.
# Used by both the dedup rake tasks and the merge migration, so the logic lives in one place.
class PipelineItems::DuplicateMerger
  STAGE_TYPE_RANK = { 'won' => 3, 'normal' => 2, 'start' => 1, 'lost' => 0 }.freeze

  def self.duplicate_groups(account_id: nil)
    scope = PipelineItem.where.not(pipeline_id: nil)
    scope = scope.where(account_id: account_id) if account_id.present?

    scope.group(:pipeline_id, :contact_id)
         .having('COUNT(*) > 1')
         .pluck(:pipeline_id, :contact_id)
         .map do |pipeline_id, contact_id|
           ids = PipelineItem.where(pipeline_id: pipeline_id, contact_id: contact_id).order(:id).pluck(:id)
           { pipeline_id: pipeline_id, contact_id: contact_id, pipeline_item_ids: ids }
         end
  end

  def self.merge_group!(pipeline_item_ids)
    items = PipelineItem.where(id: pipeline_item_ids).includes(:pipeline_stage).to_a
    new(items).merge!
  end

  def initialize(items)
    @items = items
  end

  # Winner/losers are pure sorting reads (no persistence) so they can be reused by the
  # dry-run report without mutating anything.
  def winner
    ordered.first
  end

  def losers
    ordered[1..] || []
  end

  def merge!
    return nil if @items.size < 2

    winning_item = winner
    losing_items = losers

    ActiveRecord::Base.transaction do
      stage_merged_notes(winning_item, losing_items)
      stage_conversation(winning_item, losing_items)
      stage_assignee(winning_item, losing_items)
      stage_team(winning_item, losing_items)
      stage_custom_attributes(winning_item, losing_items)
      stage_labels(winning_item, losing_items)

      # Destroy losers before saving the winner: while duplicate rows still exist in the
      # DB, PipelineItem's own uniqueness validation would reject the winner's save.
      losing_items.each(&:destroy!)
      winning_item.save!
    end

    { winner_id: winning_item.id, loser_ids: losing_items.map(&:id) }
  end

  private

  def ordered
    @ordered ||= @items.sort_by { |item| sort_key(item) }.reverse
  end

  def sort_key(item)
    stage = item.pipeline_stage
    [STAGE_TYPE_RANK.fetch(stage.stage_type, -1), stage.position, item.updated_at, item.id]
  end

  def stage_merged_notes(winning_item, losing_items)
    losing_items.sort_by(&:id).each do |loser|
      segment = "\n\n---\n[Mesclado do card ##{loser.id}, atualizado em #{loser.updated_at}]"
      segment += "\n[Card ##{loser.id} tinha valor: #{loser.value}]"
      segment += "\n#{loser.notes}" if loser.notes.present?
      winning_item.notes = "#{winning_item.notes}#{segment}"
    end
  end

  def stage_conversation(winning_item, losing_items)
    return if winning_item.conversation_id.present?

    donor = losing_items.find { |loser| loser.conversation_id.present? }
    winning_item.conversation_id = donor.conversation_id if donor
  end

  def stage_assignee(winning_item, losing_items)
    return if winning_item.assignee_id.present?

    donor = losing_items.find { |loser| loser.assignee_id.present? }
    return unless donor

    if assignee_valid_for_pipeline?(winning_item, donor.assignee_id)
      winning_item.assignee_id = donor.assignee_id
    else
      Rails.logger.warn(
        "[PipelineItems::DuplicateMerger] card ##{winning_item.id}: assignee ##{donor.assignee_id} from " \
        "merged card ##{donor.id} is not a pipeline member, skipping adoption"
      )
    end
  end

  # Reimplemented rather than reusing PipelineItem#assignee_must_be_pipeline_member's
  # User#administrator? check: that helper reads Current.account, which isn't set in a
  # rake task/migration context and would silently treat every admin as non-admin here.
  def assignee_valid_for_pipeline?(item, assignee_id)
    AccountUser.exists?(account_id: item.account_id, user_id: assignee_id, role: :administrator) ||
      item.pipeline.members.exists?(id: assignee_id)
  end

  def stage_team(winning_item, losing_items)
    return if winning_item.team_id.present?

    donor = losing_items.find { |loser| loser.team_id.present? }
    winning_item.team_id = donor.team_id if donor
  end

  def stage_custom_attributes(winning_item, losing_items)
    merged = winning_item.custom_attributes.dup
    losing_items.each do |loser|
      loser.custom_attributes.each { |key, value| merged[key] = value unless merged.key?(key) }
    end
    winning_item.custom_attributes = merged
  end

  def stage_labels(winning_item, losing_items)
    extra_labels = losing_items.flat_map(&:label_list)
    return if extra_labels.blank?

    winning_item.label_list = (winning_item.label_list + extra_labels).uniq
  end
end
