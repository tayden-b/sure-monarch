class CreateMonarchImports < ActiveRecord::Migration[8.1]
  def change
    create_table :monarch_imports, id: :uuid do |t|
      t.references :family, null: false, foreign_key: true, type: :uuid
      t.string :status, null: false, default: "pending"
      t.boolean :dry_run, null: false, default: false
      t.string :archive_name
      t.jsonb :report
      t.jsonb :reference_documents
      t.text :error
      t.timestamps
    end

    create_table :monarch_source_mappings, id: :uuid do |t|
      t.references :family, null: false, foreign_key: true, type: :uuid
      t.string :collection, null: false
      t.string :monarch_id, null: false
      t.string :record_type, null: false
      t.uuid :record_id, null: false
      t.jsonb :payload
      t.timestamps

      t.index %i[family_id collection monarch_id], unique: true,
        name: "idx_monarch_source_mappings_unique"
      t.index %i[record_type record_id],
        name: "idx_monarch_source_mappings_record"
    end
  end
end
