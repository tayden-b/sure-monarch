# Monarch's category model is a typed group -> flat category list. Sure dropped
# its income/expense classification upstream (the column was renamed to
# `classification_unused` and left in place), so this restores `classification`
# under its original name and adds real `category_groups` to carry Monarch's
# typed groups (income / expense / transfer, with order and color).
#
# Backfill: existing roots keep their preserved classification; roots created
# while the column sat unused all carry the 'expense' default, so obvious
# income names are re-marked; subcategories then inherit their parent's
# classification.
class AddCategoryGroupsAndClassification < ActiveRecord::Migration[8.1]
  def up
    create_table :category_groups, id: :uuid do |t|
      t.references :family, null: false, foreign_key: true, type: :uuid
      t.string :name, null: false
      t.string :classification, null: false
      t.integer :position
      t.string :color
      t.timestamps
    end
    add_index :category_groups, %i[family_id position]

    add_reference :categories, :category_group, type: :uuid, foreign_key: true

    rename_column :categories, :classification_unused, :classification

    # Roots created after the column was parked all carry the 'expense'
    # default — re-mark the ones that are obviously income (mirrors the set
    # the original classification migration used).
    execute <<~SQL
      UPDATE categories
      SET classification = 'income'
      WHERE parent_id IS NULL
        AND lower(name) IN ('income', 'incomes', 'other income', 'other incomes')
    SQL

    # Subcategories always share their parent's classification.
    execute <<~SQL
      UPDATE categories child
      SET classification = parent.classification
      FROM categories parent
      WHERE child.parent_id = parent.id
    SQL
  end

  def down
    rename_column :categories, :classification, :classification_unused
    remove_reference :categories, :category_group, foreign_key: true
    drop_table :category_groups
  end
end
