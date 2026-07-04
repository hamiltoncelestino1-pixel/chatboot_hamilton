json.partial! 'api/v1/models/pipeline', formats: [:json], resource: @pipeline
json.stages @pipeline.pipeline_stages do |stage|
  json.partial! 'api/v1/models/pipeline_stage', formats: [:json], resource: stage
end
