json.array! @reasons do |reason|
  json.partial! 'api/v1/models/pipeline_lost_reason', formats: [:json], resource: reason
end
