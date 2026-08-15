json.array! @tasks do |task|
  json.partial! 'api/v1/models/task', formats: [:json], resource: task
end
