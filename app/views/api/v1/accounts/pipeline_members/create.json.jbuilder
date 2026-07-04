json.array! @pipeline_members do |member|
  json.partial! 'api/v1/models/agent', formats: [:json], resource: member
end
