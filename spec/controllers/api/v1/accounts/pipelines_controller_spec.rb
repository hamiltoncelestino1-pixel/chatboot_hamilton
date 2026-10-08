# frozen_string_literal: true

require 'rails_helper'

# These examples exist to hold the OpenAPI document honest about the pipeline domain, which is
# this fork's own code and was never covered by Skooma before (claude/crm_features_fixes_tasks/
# 21-*.md). Every success path asserts conform_schema, so a field added to a jbuilder partial
# without a matching entry in swagger/definitions/ fails here instead of silently drifting -
# which is exactly how the divergences in tasks 11 and 12 went unnoticed.
RSpec.describe 'Pipelines API', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:pipeline) { create(:pipeline, account: account) }
  let!(:stage) { create(:pipeline_stage, pipeline: pipeline, account: account) }
  let!(:item) { create(:pipeline_item, pipeline_stage: stage, account: account) }
  let(:headers) { agent.create_new_auth_token }

  before { pipeline.add_members([agent.id]) }

  describe 'GET /api/v1/accounts/:account_id/pipelines' do
    it 'returns unauthorized without credentials' do
      get "/api/v1/accounts/#{account.id}/pipelines"

      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns the pipelines and conforms to the documented schema' do
      get "/api/v1/accounts/#{account.id}/pipelines", headers: headers, as: :json

      expect(response).to have_http_status(:success)
      expect(response).to conform_schema(200)
      expect(response.parsed_body.first['id']).to eq(pipeline.id)
    end
  end

  describe 'GET /api/v1/accounts/:account_id/pipelines/:id' do
    it 'returns the pipeline and conforms to the documented schema' do
      get "/api/v1/accounts/#{account.id}/pipelines/#{pipeline.id}", headers: headers, as: :json

      expect(response).to have_http_status(:success)
      expect(response).to conform_schema(200)
      expect(response.parsed_body['id']).to eq(pipeline.id)
    end
  end

  describe 'GET /api/v1/accounts/:account_id/pipelines/:id/pipeline_stages' do
    it 'returns the stages and conforms to the documented schema' do
      get "/api/v1/accounts/#{account.id}/pipelines/#{pipeline.id}/pipeline_stages",
          headers: headers, as: :json

      expect(response).to have_http_status(:success)
      expect(response).to conform_schema(200)
      # Pipeline#create_default_stages seeds stages on create, so the one built here is not
      # necessarily first - assert membership, not position.
      expect(response.parsed_body.pluck('id')).to include(stage.id)
    end
  end

  describe 'GET /api/v1/accounts/:account_id/pipelines/:id/pipeline_stages/:stage_id' do
    it 'returns a single stage and conforms to the documented schema' do
      get "/api/v1/accounts/#{account.id}/pipelines/#{pipeline.id}/pipeline_stages/#{stage.id}",
          headers: headers, as: :json

      expect(response).to have_http_status(:success)
      expect(response).to conform_schema(200)
      expect(response.parsed_body['id']).to eq(stage.id)
    end
  end

  describe 'GET /api/v1/accounts/:account_id/pipelines/:id/pipeline_items' do
    it 'returns the paginated board column and conforms to the documented schema' do
      # No `as: :json` here: with it, Rails sends params in the body even on a GET, and the
      # documented stage_id query parameter would be missing from the actual request.
      get "/api/v1/accounts/#{account.id}/pipelines/#{pipeline.id}/pipeline_items",
          params: { stage_id: stage.id }, headers: headers

      expect(response).to have_http_status(:success)
      expect(response).to conform_schema(200)
      expect(response.parsed_body['payload'].first['id']).to eq(item.id)
    end
  end

  describe 'GET /api/v1/accounts/:account_id/pipeline_items/:id' do
    it 'returns a single item and conforms to the documented schema' do
      get "/api/v1/accounts/#{account.id}/pipeline_items/#{item.id}", headers: headers, as: :json

      expect(response).to have_http_status(:success)
      expect(response).to conform_schema(200)
      expect(response.parsed_body['id']).to eq(item.id)
    end
  end
end
