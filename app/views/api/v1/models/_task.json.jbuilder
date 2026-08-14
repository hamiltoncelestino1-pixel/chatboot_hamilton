json.id resource.id
json.title resource.title
json.due_date resource.due_date.to_i
json.completed_at resource.completed_at&.to_i
json.contact_id resource.contact_id
json.conversation_id resource.conversation_id
json.pipeline_item_id resource.pipeline_item_id
json.created_at resource.created_at.to_i
json.updated_at resource.updated_at.to_i
json.assignee resource.assignee, partial: 'api/v1/models/agent', as: :resource
