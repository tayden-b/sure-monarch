class AddNeedsReviewToTransactions < ActiveRecord::Migration[8.1]
  def change
    add_column :transactions, :needs_review, :boolean, null: false, default: false

    # The review queue only ever reads flagged rows, so a partial index on
    # needs_review = true keeps the queue filter cheap without bloating the
    # index with the (vast majority) unflagged rows. Same convention as
    # index_entries_on_user_modified_true.
    add_index :transactions, :needs_review,
      name: "index_transactions_on_needs_review_true",
      where: "(needs_review = true)"
  end
end
