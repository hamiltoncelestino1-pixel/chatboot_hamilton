require 'json'

# Mirror of AutomationRules::ConditionsFilterService for rules triggered by pipeline_item
# events (task 09) - base_relation starts at PipelineItem instead of Conversation.
class AutomationRules::PipelineConditionsFilterService < FilterService
  ATTRIBUTE_MODEL = 'pipeline_item_attribute'.freeze

  # attribute_key => actual pipeline_items column, for keys that don't match 1:1.
  COLUMN_MAP = { 'stage_id' => 'pipeline_stage_id' }.freeze

  def initialize(rule, pipeline_item = nil)
    super([], nil)
    @rule = rule
    @pipeline_item = pipeline_item
    @account = pipeline_item.account

    file = File.read('./lib/filters/filter_keys.yml')
    @filters = YAML.safe_load(file)
    @pipeline_item_filters = @filters['pipeline_items']
  end

  def perform
    return false unless rule_valid?

    @rule.conditions.each_with_index do |query_hash, current_index|
      apply_filter(query_hash, current_index)
    end

    base_relation.where(@query_string, @filter_values.with_indifferent_access).any?
  rescue StandardError => e
    Rails.logger.error "Error in AutomationRules::PipelineConditionsFilterService: #{e.message}"
    Rails.logger.info "AutomationRules::PipelineConditionsFilterService failed while processing rule #{@rule.id} " \
                      "for pipeline_item #{@pipeline_item.id}"
    false
  end

  def rule_valid?
    is_valid = AutomationRules::ConditionValidationService.new(@rule).perform
    Rails.logger.info "Automation rule condition validation failed for rule id: #{@rule.id}" unless is_valid
    @rule.authorization_error! unless is_valid

    is_valid
  end

  def apply_filter(query_hash, current_index)
    pipeline_item_filter = @pipeline_item_filters[query_hash['attribute_key']]

    @query_string += pipeline_item_query_string(pipeline_item_filter, query_hash.with_indifferent_access, current_index) if pipeline_item_filter
  end

  def pipeline_item_query_string(current_filter, query_hash, current_index)
    attribute_key = query_hash['attribute_key']
    query_operator = query_hash['query_operator']
    filter_operator_value = filter_operation(query_hash, current_index)

    return build_label_query_string(query_hash, current_index, query_operator) if attribute_key == 'labels'

    case current_filter['attribute_type']
    when 'standard'
      column = COLUMN_MAP[attribute_key] || attribute_key
      " pipeline_items.#{column} #{filter_operator_value} #{query_operator} "
    end
  end

  def build_label_query_string(query_hash, current_index, query_operator)
    case query_hash['filter_operator']
    when 'equal_to'
      return " 1=0 #{query_operator} " if query_hash['values'].blank?

      value_placeholder = "value_#{current_index}"
      @filter_values[value_placeholder] = query_hash['values'].first
      " tags.name = :#{value_placeholder} #{query_operator} "
    when 'not_equal_to'
      return " 1=0 #{query_operator} " if query_hash['values'].blank?

      value_placeholder = "value_#{current_index}"
      @filter_values[value_placeholder] = query_hash['values'].first
      " tags.name != :#{value_placeholder} #{query_operator} "
    when 'is_present'
      " tags.id IS NOT NULL #{query_operator} "
    when 'is_not_present'
      " tags.id IS NULL #{query_operator} "
    else
      " tags.id #{filter_operation(query_hash, current_index)} #{query_operator} "
    end
  end

  private

  def base_relation
    records = PipelineItem.where(id: @pipeline_item.id)

    if label_conditions?
      records = records.joins(
        'LEFT OUTER JOIN taggings ON taggings.taggable_id = pipeline_items.id AND taggings.taggable_type = \'PipelineItem\''
      ).joins(
        'LEFT OUTER JOIN tags ON taggings.tag_id = tags.id'
      )
    end

    records
  end

  def label_conditions?
    @rule.conditions.any? { |condition| condition['attribute_key'] == 'labels' }
  end
end
