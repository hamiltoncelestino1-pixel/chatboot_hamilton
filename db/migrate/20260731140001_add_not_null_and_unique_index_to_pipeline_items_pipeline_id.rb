class AddNotNullAndUniqueIndexToPipelineItemsPipelineId < ActiveRecord::Migration[7.1]
  def change
    change_column_null :pipeline_items, :pipeline_id, false
    add_index :pipeline_items, %i[pipeline_id contact_id], unique: true,
                                                           name: 'index_pipeline_items_on_pipeline_id_and_contact_id'
  end
end
