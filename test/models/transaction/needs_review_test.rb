require "test_helper"

class Transaction::NeedsReviewTest < ActiveSupport::TestCase
  include EntriesTestHelper

  setup do
    @account = accounts(:depository)
  end

  test "defaults to not needing review" do
    transaction = create_transaction(account: @account).transaction

    assert_equal false, transaction.needs_review
    assert_not transaction.needs_review?
  end

  test "mark_needs_review! and mark_reviewed! toggle the flag" do
    transaction = create_transaction(account: @account).transaction

    transaction.mark_needs_review!
    assert transaction.needs_review?

    transaction.mark_reviewed!
    assert_not transaction.needs_review?
  end

  test "needs_review and excluding_needs_review scopes partition the ledger" do
    flagged = create_transaction(account: @account).transaction.tap(&:mark_needs_review!)
    clean = create_transaction(account: @account).transaction

    assert_includes Transaction.needs_review, flagged
    assert_not_includes Transaction.needs_review, clean
    assert_includes Transaction.excluding_needs_review, clean
    assert_not_includes Transaction.excluding_needs_review, flagged
  end
end
