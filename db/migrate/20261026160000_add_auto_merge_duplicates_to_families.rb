class AddAutoMergeDuplicatesToFamilies < ActiveRecord::Migration[8.1]
  def change
    add_column :families, :auto_merge_duplicates, :boolean, default: true, null: false
  end
end
