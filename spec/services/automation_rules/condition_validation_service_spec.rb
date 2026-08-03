require 'rails_helper'

RSpec.describe AutomationRules::ConditionValidationService do
  let(:account) { create(:account) }
  let(:rule) { create(:automation_rule, account: account) }

  describe '#perform' do
    context 'with standard attributes' do
      before do
        rule.conditions = [
          { 'values': ['open'], 'attribute_key': 'status', 'query_operator': nil, 'filter_operator': 'equal_to' },
          { 'values': ['+918484'], 'attribute_key': 'phone_number', 'query_operator': 'OR', 'filter_operator': 'contains' },
          { 'values': ['test'], 'attribute_key': 'email', 'query_operator': 'OR', 'filter_operator': 'contains' },
          { 'values': [true], 'attribute_key': 'private_note', 'query_operator': nil, 'filter_operator': 'equal_to' }
        ]
        rule.save
      end

      it 'returns true' do
        expect(described_class.new(rule).perform).to be(true)
      end
    end

    context 'with wrong attribute' do
      before do
        rule.conditions = [
          { 'values': ['open'], 'attribute_key': 'not-a-standard-attribute-for-sure', 'query_operator': nil, 'filter_operator': 'equal_to' }
        ]
        rule.save
      end

      it 'returns false' do
        expect(described_class.new(rule).perform).to be(false)
      end
    end

    context 'with wrong filter operator' do
      before do
        rule.conditions = [
          { 'values': ['open'], 'attribute_key': 'status', 'query_operator': nil, 'filter_operator': 'not-a-filter-operator' }
        ]
        rule.save
      end

      it 'returns false' do
        expect(described_class.new(rule).perform).to be(false)
      end
    end

    context 'with wrong query operator' do
      before do
        rule.conditions = [{ 'values': ['open'], 'attribute_key': 'status', 'query_operator': 'invalid', 'filter_operator': 'attribute_changed' }]
        rule.save
      end

      it 'returns false' do
        expect(described_class.new(rule).perform).to be(false)
      end
    end

    context 'with "attribute_changed" filter operator' do
      before do
        rule.conditions = [
          { 'values': ['open'], 'attribute_key': 'status', 'query_operator': nil, 'filter_operator': 'attribute_changed' }
        ]
        rule.save
      end

      it 'returns true' do
        expect(described_class.new(rule).perform).to be(true)
      end
    end

    context 'with correct custom attribute' do
      before do
        create(:custom_attribute_definition,
               attribute_key: 'custom_attr_priority',
               account: account,
               attribute_model: 'conversation_attribute',
               attribute_display_type: 'list',
               attribute_values: %w[P0 P1 P2])

        rule.conditions = [
          {
            'values': ['true'],
            'attribute_key': 'custom_attr_priority',
            'filter_operator': 'equal_to',
            'custom_attribute_type': 'conversation_attribute'
          }
        ]
        rule.save
      end

      it 'returns true' do
        expect(described_class.new(rule).perform).to be(true)
      end
    end

    context 'with missing custom attribute' do
      before do
        rule.conditions = [
          {
            'values': ['true'],
            'attribute_key': 'attribute_is_not_present', # the attribute is not present
            'filter_operator': 'equal_to',
            'custom_attribute_type': 'conversation_attribute'
          }
        ]
        rule.save
      end

      it 'returns false for missing custom attribute' do
        expect(described_class.new(rule).perform).to be(false)
      end
    end

    context 'with a custom attribute condition that omits custom_attribute_type (fallback)' do
      it 'falls back to conversation_attribute for a conversation-triggered rule' do
        create(:custom_attribute_definition,
               attribute_key: 'custom_attr_priority',
               account: account,
               attribute_model: 'conversation_attribute',
               attribute_display_type: 'list',
               attribute_values: %w[P0 P1 P2])
        rule.conditions = [
          { 'values': ['true'], 'attribute_key': 'custom_attr_priority', 'filter_operator': 'equal_to' }
        ]
        rule.save

        expect(described_class.new(rule).perform).to be(true)
      end

      # AutomationRules::PipelineConditionsFilterService::ATTRIBUTE_MODEL ('pipeline_item_attribute')
      # never overrides this class's own ATTRIBUTE_MODEL by polymorphism - the two aren't in the
      # same inheritance chain - so the fallback has to branch on the rule's event_name instead.
      # No pipeline custom attribute condition exists in the UI yet, so this is a regression
      # guard for when it does, not a currently-exercised production path.
      it 'falls back to pipeline_item_attribute for a pipeline_item-triggered rule' do
        pipeline_rule = create(:automation_rule, account: account, event_name: 'pipeline_item_created', conditions: [])
        create(:custom_attribute_definition,
               attribute_key: 'custom_attr_deal_source',
               account: account,
               attribute_model: 'pipeline_item_attribute',
               attribute_display_type: 'list',
               attribute_values: %w[ads referral])
        pipeline_rule.conditions = [
          { 'values': ['true'], 'attribute_key': 'custom_attr_deal_source', 'filter_operator': 'equal_to' }
        ]
        pipeline_rule.save

        expect(described_class.new(pipeline_rule).perform).to be(true)
      end
    end
  end
end
