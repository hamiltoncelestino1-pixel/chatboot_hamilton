json.array! @items do |item|
  json.partial! 'api/v1/models/pipeline_item', formats: [:json], resource: item,
                                               overdue_tasks_counts: @overdue_tasks_counts
end
