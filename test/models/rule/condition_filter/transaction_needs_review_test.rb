require "test_helper"

class Rule::ConditionFilter::TransactionNeedsReviewTest < ActiveSupport::TestCase
  include EntriesTestHelper

  setup do
    @rule = rules(:one)
    @filter = Rule::ConditionFilter::TransactionNeedsReview.new(@rule)
  end

  test "offers needs review and reviewed options" do
    assert_equal "select", @filter.type
    assert_equal [
      [ "Needs review", "needs_review" ],
      [ "Reviewed", "reviewed" ]
    ], @filter.options
    assert_equal 1, @filter.operators.length
  end

  test "apply scopes to flagged and reviewed transactions" do
    flagged = create_transaction(account: accounts(:depository))
    flagged.transaction.mark_needs_review!
    clean = create_transaction(account: accounts(:depository))

    needs = @filter.apply(Transaction.all, "=", "needs_review")
    assert_includes needs, flagged.transaction
    assert_not_includes needs, clean.transaction

    reviewed = @filter.apply(Transaction.all, "=", "reviewed")
    assert_includes reviewed, clean.transaction
    assert_not_includes reviewed, flagged.transaction
  end
end
