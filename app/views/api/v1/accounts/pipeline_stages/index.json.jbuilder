json.array! @stages do |stage|
  json.partial! 'api/v1/models/pipeline_stage', formats: [:json], resource: stage, items_counts: @items_counts
end
