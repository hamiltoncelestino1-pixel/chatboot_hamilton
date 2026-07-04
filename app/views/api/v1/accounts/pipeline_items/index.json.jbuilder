json.array! @items do |item|
  json.partial! 'api/v1/models/pipeline_item', formats: [:json], resource: item
end
