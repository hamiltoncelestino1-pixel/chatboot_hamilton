class AddMacroTypeToMacros < ActiveRecord::Migration[7.1]
  def change
    add_column :macros, :macro_type, :integer, default: 0, null: false
  end
end
