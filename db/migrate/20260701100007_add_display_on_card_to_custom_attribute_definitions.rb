class AddDisplayOnCardToCustomAttributeDefinitions < ActiveRecord::Migration[7.1]
  def change
    add_column :custom_attribute_definitions, :display_on_card, :boolean, null: false, default: false
  end
end
