require "test_helper"
require "ostruct"

class PlaidItem::ImporterTest < ActiveSupport::TestCase
  setup do
    @mock_provider = mock("Provider::Plaid")
    @plaid_item = plaid_items(:one)
    @importer = PlaidItem::Importer.new(@plaid_item, plaid_provider: @mock_provider)
  end

  test "imports item metadata" do
    item_data = OpenStruct.new(
      item_id: "item_1",
      available_products: [ "transactions", "investments", "liabilities" ],
      billed_products: [],
      institution_id: "ins_1",
      institution_name: "First Platypus Bank",
    )

    @mock_provider.expects(:get_item).with(@plaid_item.access_token).returns(
      OpenStruct.new(item: item_data)
    )

    institution_data = OpenStruct.new(
      institution_id: "ins_1",
      institution_name: "First Platypus Bank",
    )

    @mock_provider.expects(:get_institution).with("ins_1").returns(
      OpenStruct.new(institution: institution_data)
    )

    PlaidItem::AccountsSnapshot.any_instance.expects(:accounts).returns([
      OpenStruct.new(
        account_id: "acc_1",
        type: "depository",
      )
    ]).at_least_once

    PlaidItem::AccountsSnapshot.any_instance.expects(:transactions_cursor).returns("test_cursor_1")

    PlaidItem::AccountsSnapshot.any_instance.expects(:get_account_data).with("acc_1").once

    PlaidAccount::Importer.any_instance.expects(:import).once

    @plaid_item.expects(:update!).with(next_cursor: "test_cursor_1")
    @plaid_item.expects(:upsert_plaid_snapshot!).with(item_data)
    @plaid_item.expects(:upsert_plaid_institution_snapshot!).with(institution_data)

    @importer.import
  end

  test "clears requires update status after a successful import" do
    @plaid_item.update!(status: :requires_update)
    @importer.stubs(:fetch_and_import_item_data)
    @importer.stubs(:fetch_and_import_accounts_data)

    @importer.import

    assert_predicate @plaid_item.reload, :good?
  end

  test "keeps requires update status when login is still required" do
    @plaid_item.update!(status: :requires_update)
    error = Plaid::ApiError.new(
      code: 400,
      response_body: { "error_code" => "ITEM_LOGIN_REQUIRED" }.to_json
    )
    @importer.stubs(:fetch_and_import_item_data).raises(error)
    @importer.expects(:fetch_and_import_accounts_data).never

    @importer.import

    assert_predicate @plaid_item.reload, :requires_update?
  end

  test "a declined optional product does not fail the import" do
    @importer.stubs(:fetch_and_import_item_data)
    @plaid_item.update!(available_products: %w[transactions liabilities], billed_products: [])

    @mock_provider.expects(:get_item_accounts).with(@plaid_item.access_token).returns(
      OpenStruct.new(accounts: [
        OpenStruct.new(
          account_id: "acc_1",
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
    @mock_provider.expects(:get_item_liabilities).raises(
      Plaid::ApiError.new(
        code: 400,
        response_body: { "error_code" => "ADDITIONAL_CONSENT_REQUIRED" }.to_json
      )
    )

    assert_difference -> { DebugLogEntry.count }, 1 do
      @importer.import
    end

    assert @plaid_item.plaid_accounts.find_by(plaid_id: "acc_1").persisted?,
      "accounts should still import when an optional product is declined"
    assert_equal "ADDITIONAL_CONSENT_REQUIRED",
      @plaid_item.reload.unavailable_products.dig("liabilities", "error_code")
    assert_predicate @plaid_item, :good?
  end

  test "missing transactions consent fails the import and flags the item for reconnect" do
    @importer.stubs(:fetch_and_import_item_data)
    @plaid_item.update!(available_products: %w[transactions], billed_products: [])

    @mock_provider.expects(:get_item_accounts).with(@plaid_item.access_token).returns(
      OpenStruct.new(accounts: [ OpenStruct.new(account_id: "acc_1", type: "depository") ])
    )
    @mock_provider.expects(:get_transactions).raises(
      Plaid::ApiError.new(
        code: 400,
        response_body: { "error_code" => "ADDITIONAL_CONSENT_REQUIRED" }.to_json
      )
    )

    PlaidAccount::Importer.any_instance.expects(:import).never

    assert_difference -> { DebugLogEntry.count }, 1 do
      assert_raises(PlaidItem::ConsentRequiredError) { @importer.import }
    end

    assert_predicate @plaid_item.reload, :requires_update?
  end
end
