require "test_helper"
require "ostruct"

class PlaidItem::SyncerTest < ActiveSupport::TestCase
  setup do
    @plaid_item = plaid_items(:one)
    @mock_provider = mock("Provider::Plaid")

    Provider::Registry.stubs(:plaid_provider_for_region).returns(@mock_provider)
    PlaidItem::Importer.any_instance.stubs(:fetch_and_import_item_data)
    PlaidItem.any_instance.stubs(:perform_post_sync)
    PlaidItem.any_instance.stubs(:broadcast_sync_complete)
    PlaidItem.any_instance.stubs(:process_accounts)
    PlaidItem.any_instance.stubs(:schedule_account_syncs)
    Sentry.stubs(:capture_exception)
  end

  test "a declined optional product does not fail the item sync" do
    @plaid_item.update!(available_products: %w[transactions liabilities], billed_products: [])

    @mock_provider.expects(:get_item_accounts).with(@plaid_item.access_token).returns(
      OpenStruct.new(accounts: [
        OpenStruct.new(
          account_id: "acc_cc",
          type: "credit",
          subtype: "credit card",
          name: "Test Credit Card",
          mask: "1234",
          balances: OpenStruct.new(current: 100, available: 80, iso_currency_code: "USD")
        )
      ])
    )
    @mock_provider.expects(:get_transactions).returns(
      OpenStruct.new(added: [], modified: [], removed: [], cursor: "cursor_1")
    )
    @mock_provider.expects(:get_item_liabilities).with(@plaid_item.access_token).raises(
      plaid_error("ADDITIONAL_CONSENT_REQUIRED")
    )

    sync = @plaid_item.syncs.create!
    sync.perform

    assert_predicate sync.reload, :completed?
    assert_predicate @plaid_item.reload, :good?
    assert_equal "ADDITIONAL_CONSENT_REQUIRED",
      @plaid_item.unavailable_products.dig("liabilities", "error_code")
    assert DebugLogEntry.where(category: "provider_sync", level: "warn")
      .where("metadata ->> 'product' = ?", "liabilities").exists?
  end

  test "missing consent on the core transactions product fails the sync with a reconnect message" do
    @plaid_item.update!(available_products: %w[transactions], billed_products: [])

    @mock_provider.expects(:get_item_accounts).with(@plaid_item.access_token).returns(
      OpenStruct.new(accounts: [ OpenStruct.new(account_id: "acc_dep", type: "depository") ])
    )
    @mock_provider.expects(:get_transactions).raises(
      plaid_error("ADDITIONAL_CONSENT_REQUIRED")
    )

    sync = @plaid_item.syncs.create!
    sync.perform

    assert_predicate sync.reload, :failed?
    assert_match(/reconnect/i, sync.error)
    assert_match(/transactions/i, sync.error)
    refute_match(/response_body|error_code/i, sync.error)
    assert_predicate @plaid_item.reload, :requires_update?
    assert DebugLogEntry.where(category: "provider_sync", level: "error")
      .where("metadata ->> 'product' = ?", "transactions").exists?
  end

  private

    def plaid_error(error_code, type: "INVALID_INPUT")
      Plaid::ApiError.new(
        code: 400,
        response_body: {
          "error_type" => type,
          "error_code" => error_code,
          "error_message" => "Plaid error"
        }.to_json
      )
    end
end
