# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Pipeline Items API', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:source_pipeline) { create(:pipeline, account: account) }
  let(:source_stage) { create(:pipeline_stage, pipeline: source_pipeline, account: account) }
  let(:target_pipeline) { create(:pipeline, account: account) }
  let(:target_stage) { create(:pipeline_stage, pipeline: target_pipeline, account: account) }
  let(:item) { create(:pipeline_item, pipeline_stage: source_stage, account: account) }

  before do
    source_pipeline.add_members([agent.id])
    target_pipeline.add_members([agent.id])
    item # force creation before tests
  end

  describe 'POST /api/v1/accounts/:account_id/pipeline_items' do
    context 'when authenticated' do
      let(:headers) { agent.create_new_auth_token }

      it 'returns 422 with the duplicate-card message when the contact already has a card in the pipeline' do
        existing_item = item
        contact = existing_item.contact

        post "/api/v1/accounts/#{account.id}/pipeline_items",
             params: {
               pipeline_item: {
                 pipeline_stage_id: source_stage.id,
                 contact_id: contact.id
               }
             },
             headers: headers,
             as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['message']).to include(
          I18n.t('errors.pipeline_item.duplicate_contact_in_pipeline')
        )
      end
    end
  end

  describe 'POST /api/v1/accounts/:account_id/pipeline_items/:id/export' do
    context 'when unauthenticated' do
      it 'returns unauthorized' do
        post "/api/v1/accounts/#{account.id}/pipeline_items/#{item.id}/export"
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when authenticated' do
      let(:headers) { agent.create_new_auth_token }

      it 'exports the item to the target pipeline and stage' do
        post "/api/v1/accounts/#{account.id}/pipeline_items/#{item.id}/export",
             params: { pipeline_item: { target_pipeline_id: target_pipeline.id, target_stage_id: target_stage.id } },
             headers: headers,
             as: :json

        expect(response).to have_http_status(:success)
        expect(item.reload.pipeline_stage_id).to eq(target_stage.id)
        expect(response.parsed_body['id']).to eq(item.id)
      end

      it 'returns 404 when target_pipeline_id is inaccessible' do
        other_account_pipeline = create(:pipeline)
        post "/api/v1/accounts/#{account.id}/pipeline_items/#{item.id}/export",
             params: { pipeline_item: { target_pipeline_id: other_account_pipeline.id, target_stage_id: target_stage.id } },
             headers: headers,
             as: :json

        expect(response).to have_http_status(:not_found)
      end

      it 'returns 422 when target_stage_id does not belong to target_pipeline' do
        other_stage = create(:pipeline_stage, account: account)
        post "/api/v1/accounts/#{account.id}/pipeline_items/#{item.id}/export",
             params: { pipeline_item: { target_pipeline_id: target_pipeline.id, target_stage_id: other_stage.id } },
             headers: headers,
             as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['error']).to be_present
      end

      it 'returns 422 when target_pipeline is the same as the source pipeline' do
        post "/api/v1/accounts/#{account.id}/pipeline_items/#{item.id}/export",
             params: { pipeline_item: { target_pipeline_id: source_pipeline.id, target_stage_id: source_stage.id } },
             headers: headers,
             as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['error']).to be_present
      end
    end
  end
end
