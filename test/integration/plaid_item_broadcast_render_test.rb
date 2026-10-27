require "test_helper"

class PlaidItemBroadcastRenderTest < ActiveSupport::TestCase
  # PlaidItem::SyncCompleteEvent#broadcast re-renders this partial from the
  # sync job, outside any request, so Current.user is nil there. A
  # viewer-dependent filter in the partial would silently empty the account
  # list for every family member on every completed sync.
  test "the connection card still renders its accounts with no current user" do
    item = plaid_items(:one)
    account = item.accounts.first
    assert account.present?, "fixture item needs at least one account"

    Current.reset
    assert_nil Current.user

    html = ApplicationController.render(
      partial: "plaid_items/plaid_item",
      locals: { plaid_item: item }
    )

    assert_includes html, account.name
  end

  test "shows the not-shared notice with a reconnect link for declined products" do
    item = plaid_items(:one)
    item.update!(raw_payload: {
      PlaidItem::PARTIAL_CONSENT_KEY => {
        "liabilities" => { "error_code" => "ADDITIONAL_CONSENT_REQUIRED", "retryable" => false }
      }
    })

    Current.session = Session.create!(user: users(:family_admin))

    html = ApplicationController.render(
      partial: "plaid_items/plaid_item",
      locals: { plaid_item: item }
    )

    assert_includes html, "Liabilities data not shared"
    assert_includes html, "Reconnect"
    assert_includes html, "/plaid_items/#{item.id}/edit"
  ensure
    Current.reset
  end

  test "shows the retry notice instead for temporarily unavailable products" do
    item = plaid_items(:one)
    item.update!(raw_payload: {
      PlaidItem::PARTIAL_CONSENT_KEY => {
        "investments" => { "error_code" => "PRODUCT_NOT_READY", "retryable" => true }
      }
    })

    html = ApplicationController.render(
      partial: "plaid_items/plaid_item",
      locals: { plaid_item: item }
    )

    assert_includes html, "temporarily unavailable"
    assert_not_includes html, "Reconnect"
  end

  test "shows no notice when no products are flagged" do
    item = plaid_items(:one)

    html = ApplicationController.render(
      partial: "plaid_items/plaid_item",
      locals: { plaid_item: item }
    )

    assert_not_includes html, "data not shared"
    assert_not_includes html, "temporarily unavailable"
  end
end
