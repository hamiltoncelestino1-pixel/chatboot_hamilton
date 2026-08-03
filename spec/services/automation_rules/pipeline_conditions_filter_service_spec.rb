require 'rails_helper'

RSpec.describe AutomationRules::PipelineConditionsFilterService do
  let(:account) { create(:account) }
  let(:pipeline) { create(:pipeline, account: account) }
  let(:stage) { pipeline.pipeline_stages.find_by(stage_type: :start) }
  let(:other_stage) { pipeline.pipeline_stages.find_by(stage_type: :won) }
  let(:contact) { create(:contact, account: account) }
  let(:item) { create(:pipeline_item, pipeline_stage: stage, account: account, contact: contact, value: 500) }
  let(:rule) { create(:automation_rule, account: account, event_name: 'pipeline_item_stage_changed', conditions: []) }

  describe '#perform' do
    context 'when filtering by stage_id' do
      it 'returns true when the card is in the given stage' do
        rule.update!(conditions: [{ 'values' => [stage.id], 'attribute_key' => 'stage_id', 'query_operator' => nil,
                                    'filter_operator' => 'equal_to' }])

        expect(described_class.new(rule, item).perform).to be(true)
      end

      it 'returns false when the card is in a different stage' do
        rule.update!(conditions: [{ 'values' => [other_stage.id], 'attribute_key' => 'stage_id', 'query_operator' => nil,
                                    'filter_operator' => 'equal_to' }])

        expect(described_class.new(rule, item).perform).to be(false)
      end
    end

    context 'when filtering by pipeline_id' do
      it 'returns true when the card belongs to the given pipeline' do
        rule.update!(conditions: [{ 'values' => [pipeline.id], 'attribute_key' => 'pipeline_id', 'query_operator' => nil,
                                    'filter_operator' => 'equal_to' }])

        expect(described_class.new(rule, item).perform).to be(true)
      end

      it 'returns false when the card belongs to a different pipeline' do
        other_pipeline = create(:pipeline, account: account)
        rule.update!(conditions: [{ 'values' => [other_pipeline.id], 'attribute_key' => 'pipeline_id', 'query_operator' => nil,
                                    'filter_operator' => 'equal_to' }])

        expect(described_class.new(rule, item).perform).to be(false)
      end
    end

    context 'when filtering by value' do
      it 'returns true when the value is greater than the given threshold' do
        rule.update!(conditions: [{ 'values' => [100], 'attribute_key' => 'value', 'query_operator' => nil, 'filter_operator' => 'is_greater_than' }])

        expect(described_class.new(rule, item).perform).to be(true)
      end

      it 'returns false when the value is not greater than the given threshold' do
        rule.update!(conditions: [{ 'values' => [1000], 'attribute_key' => 'value', 'query_operator' => nil,
                                    'filter_operator' => 'is_greater_than' }])

        expect(described_class.new(rule, item).perform).to be(false)
      end
    end

    context 'when filtering by assignee_id' do
      it 'returns true when the card has an assignee' do
        agent = create(:user, account: account, role: :agent)
        create(:pipeline_member, pipeline: pipeline, user: agent)
        item.update!(assignee_id: agent.id)
        rule.update!(conditions: [{ 'values' => [], 'attribute_key' => 'assignee_id', 'query_operator' => nil, 'filter_operator' => 'is_present' }])

        expect(described_class.new(rule, item).perform).to be(true)
      end

      it 'returns false when the card has no assignee' do
        rule.update!(conditions: [{ 'values' => [], 'attribute_key' => 'assignee_id', 'query_operator' => nil, 'filter_operator' => 'is_present' }])

        expect(described_class.new(rule, item).perform).to be(false)
      end
    end

    context 'when filtering by team_id' do
      it 'returns true when the card is assigned to the given team' do
        team = create(:team, account: account)
        item.update!(team_id: team.id)
        rule.update!(conditions: [{ 'values' => [team.id], 'attribute_key' => 'team_id', 'query_operator' => nil, 'filter_operator' => 'equal_to' }])

        expect(described_class.new(rule, item).perform).to be(true)
      end
    end

    context 'when filtering by labels' do
      before do
        create(:label, account: account, title: 'quente', label_type: :pipeline_label)
        item.label_list = ['quente']
        item.save!(validate: false)
      end

      it 'returns true when the card has the label' do
        rule.update!(conditions: [{ 'values' => ['quente'], 'attribute_key' => 'labels', 'query_operator' => nil, 'filter_operator' => 'equal_to' }])

        expect(described_class.new(rule, item).perform).to be(true)
      end

      it 'returns false when the card does not have the label' do
        rule.update!(conditions: [{ 'values' => ['frio'], 'attribute_key' => 'labels', 'query_operator' => nil, 'filter_operator' => 'equal_to' }])

        expect(described_class.new(rule, item).perform).to be(false)
      end
    end
  end
end
