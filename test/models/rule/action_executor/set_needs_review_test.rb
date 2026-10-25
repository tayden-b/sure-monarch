require "test_helper"

class Rule::ActionExecutor::SetNeedsReviewTest < ActiveSupport::TestCase
  include EntriesTestHelper

  setup do
    @rule = rules(:one)
    @executor = Rule::ActionExecutor::SetNeedsReview.new(@rule)
  end

  test "offers needs review and reviewed options" do
    assert_equal "select", @executor.type
    assert_equal [
      [ "Needs review", "needs_review" ],
      [ "Reviewed", "reviewed" ]
    ], @executor.options
  end

  test "flags and unflags scoped transactions in both directions" do
    first = create_transaction(account: accounts(:depository))
    second = create_transaction(account: accounts(:depository))
    scope = Transaction.where(id: [ first.transaction.id, second.transaction.id ])

    assert_equal 2, @executor.execute(scope, value: "needs_review")
    assert first.transaction.reload.needs_review?
    assert second.transaction.reload.needs_review?

    assert_equal 2, @executor.execute(scope, value: "reviewed")
    assert_not first.transaction.reload.needs_review?
    assert_not second.transaction.reload.needs_review?
  end

  test "idempotent: re-flagging an already flagged transaction counts zero" do
    entry = create_transaction(account: accounts(:depository))
    entry.transaction.mark_needs_review!
    scope = Transaction.where(id: entry.transaction.id)

    assert_equal 0, @executor.execute(scope, value: "needs_review")
  end

  test "rejects unknown values" do
    transaction = entries(:transaction).transaction
    scope = Transaction.where(id: transaction.id)

    assert_equal 0, @executor.execute(scope, value: "bogus")
    assert_not transaction.reload.needs_review?
  end
end
