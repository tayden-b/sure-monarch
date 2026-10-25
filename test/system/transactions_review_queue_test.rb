require "application_system_test_case"

class TransactionsReviewQueueTest < ApplicationSystemTestCase
  include EntriesTestHelper
  include ActionView::RecordIdentifier

  setup do
    sign_in @user = users(:family_admin)

    Entry.delete_all # clean slate

    @flagged = create_transaction(
      account: accounts(:depository),
      name: "Flagged transaction",
      date: Date.current,
      amount: 50
    )
    @flagged.transaction.mark_needs_review!

    @clean = create_transaction(
      account: accounts(:depository),
      name: "Clean transaction",
      date: Date.current,
      amount: 60
    )

    visit transactions_url
  end

  test "review queue chip filters to flagged rows" do
    assert_text "Needs review (1)"

    click_on "Needs review (1)"

    assert_selector "#" + dom_id(@flagged), count: 1
    assert_no_selector "#" + dom_id(@clean)

    within "#" + dom_id(@flagged) do
      assert_text "Needs review"
    end
  end

  test "review filter narrows the feed to needs_review rows" do
    find("#transaction-filters-button").click

    within "#transaction-filters-menu" do
      click_button "Review"
      check "Needs review"
      click_button "Apply"
    end

    assert_selector "#" + dom_id(@flagged), count: 1
    assert_no_selector "#" + dom_id(@clean)
  end
end
