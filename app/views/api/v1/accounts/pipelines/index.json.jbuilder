json.array! @pipelines do |pipeline|
  json.partial! 'api/v1/models/pipeline', formats: [:json], resource: pipeline
  json.stages pipeline.pipeline_stages do |stage|
    json.partial! 'api/v1/models/pipeline_stage', formats: [:json], resource: stage, items_counts: @items_counts
  end
end
