require 'rails_helper'

RSpec.describe PipelineItems::DuplicateMerger do
  let(:account) { create(:account) }
  let(:pipeline) { create(:pipeline, account: account) }
  let(:contact) { create(:contact, account: account) }

  # This spec's whole point is to fabricate duplicate (pipeline_id, contact_id) cards, i.e.
  # exactly the legacy state task 01/02's own DB unique index now forbids. Dropping it here
  # is safe: transactional fixtures roll back every DDL change (Postgres supports
  # transactional DDL) at the end of each example, so the real index is untouched afterwards.
  before do
    ActiveRecord::Base.connection.remove_index(:pipeline_items, name: 'index_pipeline_items_on_pipeline_id_and_contact_id')
  end

  # Pipeline#create_default_stages already creates one start/won/lost stage per pipeline
  # (stage_type is unique per pipeline unless normal), so reuse those instead of creating more.
  def stage(type, position: nil)
    return pipeline.pipeline_stages.find_by!(stage_type: type) unless type == :normal

    attrs = { pipeline: pipeline, account: account }
    attrs[:position] = position if position
    create(:pipeline_stage, **attrs)
  end

  # Duplicates are exactly what PipelineItem's own uniqueness validation (task 01) now
  # rejects on save — but that's the legacy data this class exists to clean up, so fixtures
  # must bypass validation to simulate cards that already existed before the rule shipped.
  def item_for(pipeline_stage, **attrs)
    item = build(:pipeline_item, pipeline_stage: pipeline_stage, account: account, contact: contact, **attrs)
    item.pipeline_id = pipeline_stage.pipeline_id
    item.save!(validate: false)
    item
  end

  describe '#winner / #losers (ranking, no persistence)' do
    it 'picks the won card over normal, start and lost' do
      lost_item = item_for(stage(:lost))
      start_item = item_for(stage(:start))
      won_item = item_for(stage(:won))

      merger = described_class.new([lost_item, start_item, won_item])

      expect(merger.winner).to eq(won_item)
      expect(merger.losers).to contain_exactly(lost_item, start_item)
    end

    it 'breaks ties between normal stages by the most advanced stage position' do
      early_normal = item_for(stage(:normal, position: 0))
      late_normal = item_for(stage(:normal, position: 1))

      merger = described_class.new([early_normal, late_normal])

      expect(merger.winner).to eq(late_normal)
    end

    it 'breaks ties within the same stage by the most recently updated_at' do
      normal_stage = stage(:normal)
      older = item_for(normal_stage, updated_at: 2.days.ago)
      newer = item_for(normal_stage, updated_at: 1.hour.ago)

      merger = described_class.new([older, newer])

      expect(merger.winner).to eq(newer)
    end

    it 'breaks residual ties by the highest id' do
      normal_stage = stage(:normal)
      now = Time.current
      first = item_for(normal_stage, updated_at: now)
      second = item_for(normal_stage, updated_at: now)

      merger = described_class.new([first, second])

      expect(merger.winner).to eq(second)
    end

    it 'does not touch the database' do
      lost_item = item_for(stage(:lost))
      won_item = item_for(stage(:won))

      expect { described_class.new([lost_item, won_item]).winner }.not_to change(PipelineItem, :count)
      expect(PipelineItem.exists?(lost_item.id)).to be true
    end
  end

  describe '#merge!' do
    it 'returns nil and changes nothing when there is only one item' do
      solo = item_for(stage(:normal))

      expect(described_class.new([solo]).merge!).to be_nil
      expect(PipelineItem.exists?(solo.id)).to be true
    end

    it 'destroys the losers and keeps only the winner' do
      loser = item_for(stage(:start))
      winner = item_for(stage(:won))

      result = described_class.new([loser, winner]).merge!

      expect(result).to eq(winner_id: winner.id, loser_ids: [loser.id])
      expect(PipelineItem.exists?(loser.id)).to be false
      expect(PipelineItem.exists?(winner.id)).to be true
    end

    it 'concatenates loser notes and value onto the winner, marked and never silently dropped' do
      loser = item_for(stage(:start), notes: 'nota do perdedor', value: 250.0)
      winner = item_for(stage(:won), notes: 'nota do vencedor')

      described_class.new([loser, winner]).merge!
      winner.reload

      expect(winner.notes).to start_with('nota do vencedor')
      expect(winner.notes).to include("Mesclado do card ##{loser.id}")
      expect(winner.notes).to include("Card ##{loser.id} tinha valor: 250.0")
      expect(winner.notes).to include('nota do perdedor')
    end

    it 'keeps the winner value untouched (never summed)' do
      loser = item_for(stage(:start), value: 999.0)
      winner = item_for(stage(:won), value: 100.0)

      described_class.new([loser, winner]).merge!
      winner.reload

      expect(winner.value).to eq(100.0)
    end

    it 'shallow-merges custom_attributes, letting the winner keep its own values' do
      loser = item_for(stage(:start), custom_attributes: { 'source' => 'loser', 'campaign' => 'summer' })
      winner = item_for(stage(:won), custom_attributes: { 'source' => 'winner' })

      described_class.new([loser, winner]).merge!
      winner.reload

      expect(winner.custom_attributes).to eq('source' => 'winner', 'campaign' => 'summer')
    end

    it 'unions pipeline labels from winner and losers' do
      create(:label, account: account, title: 'quente', label_type: :pipeline_label)
      create(:label, account: account, title: 'frio', label_type: :pipeline_label)
      loser = item_for(stage(:start))
      loser.label_list = ['frio']
      loser.save!(validate: false)
      winner = item_for(stage(:won))
      winner.label_list = ['quente']
      winner.save!(validate: false)

      described_class.new([loser, winner]).merge!
      winner.reload

      expect(winner.label_list).to contain_exactly('quente', 'frio')
    end

    it "adopts the loser's conversation_id when the winner has none" do
      conversation = create(:conversation, account: account, contact: contact)
      loser = item_for(stage(:start), conversation: conversation)
      winner = item_for(stage(:won))

      described_class.new([loser, winner]).merge!
      winner.reload

      expect(winner.conversation_id).to eq(conversation.id)
    end

    it 'keeps the winner conversation_id when it already has one' do
      winner_conversation = create(:conversation, account: account, contact: contact)
      loser_conversation = create(:conversation, account: account, contact: contact)
      loser = item_for(stage(:start), conversation: loser_conversation)
      winner = item_for(stage(:won), conversation: winner_conversation)

      described_class.new([loser, winner]).merge!
      winner.reload

      expect(winner.conversation_id).to eq(winner_conversation.id)
    end

    it "adopts the loser's assignee when the winner has none and the assignee is a pipeline member" do
      agent = create(:user, account: account, role: :agent)
      create(:pipeline_member, pipeline: pipeline, user: agent)
      loser = item_for(stage(:start), assignee: agent)
      winner = item_for(stage(:won))

      described_class.new([loser, winner]).merge!
      winner.reload

      expect(winner.assignee_id).to eq(agent.id)
    end

    it "skips adopting the loser's assignee when they are not a pipeline member, without failing the merge" do
      outsider = create(:user, account: account, role: :agent)
      loser = item_for(stage(:start), assignee: outsider)
      winner = item_for(stage(:won))

      allow(Rails.logger).to receive(:warn)

      result = described_class.new([loser, winner]).merge!
      winner.reload

      expect(result).to eq(winner_id: winner.id, loser_ids: [loser.id])
      expect(winner.assignee_id).to be_nil
      expect(Rails.logger).to have_received(:warn).with(/not a pipeline member/)
    end

    it "adopts the loser's team_id when the winner has none" do
      team = create(:team, account: account)
      loser = item_for(stage(:start), team: team)
      winner = item_for(stage(:won))

      described_class.new([loser, winner]).merge!
      winner.reload

      expect(winner.team_id).to eq(team.id)
    end

    it 'is idempotent: merging an already-merged group is a no-op' do
      loser = item_for(stage(:start))
      winner = item_for(stage(:won))

      first_result = described_class.merge_group!([loser.id, winner.id])
      second_result = described_class.merge_group!([loser.id, winner.id])

      expect(first_result).to eq(winner_id: winner.id, loser_ids: [loser.id])
      expect(second_result).to be_nil
    end
  end

  describe '.duplicate_groups' do
    it 'finds groups with more than one card for the same contact and pipeline' do
      loser = item_for(stage(:start))
      winner = item_for(stage(:won))
      other_contact = create(:contact, account: account)
      item_for(stage(:normal), contact: other_contact)

      groups = described_class.duplicate_groups

      expect(groups.size).to eq(1)
      expect(groups.first[:pipeline_id]).to eq(pipeline.id)
      expect(groups.first[:contact_id]).to eq(contact.id)
      expect(groups.first[:pipeline_item_ids]).to contain_exactly(loser.id, winner.id)
    end

    it 'scopes results to the given account_id' do
      item_for(stage(:start))
      item_for(stage(:won))
      other_account = create(:account)
      other_pipeline = create(:pipeline, account: other_account)
      other_stage = create(:pipeline_stage, pipeline: other_pipeline, account: other_account)
      other_contact = create(:contact, account: other_account)
      other_item = build(:pipeline_item, pipeline_stage: other_stage, account: other_account, contact: other_contact)
      other_item.pipeline_id = other_pipeline.id
      other_item.save!(validate: false)
      duplicate_item = build(:pipeline_item, pipeline_stage: other_stage, account: other_account, contact: other_contact)
      duplicate_item.pipeline_id = other_pipeline.id
      duplicate_item.save!(validate: false)

      groups = described_class.duplicate_groups(account_id: account.id)

      expect(groups.size).to eq(1)
      expect(groups.first[:pipeline_id]).to eq(pipeline.id)
    end
  end
end
