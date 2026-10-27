require "test_helper"

class PlaidItem::AccountsSnapshotTest < ActiveSupport::TestCase
  setup do
    @plaid_item = plaid_items(:one)
    @plaid_item.plaid_accounts.destroy_all # Clean slate

    @plaid_provider = mock
    @snapshot = PlaidItem::AccountsSnapshot.new(@plaid_item, plaid_provider: @plaid_provider)
  end

  test "fetches accounts" do
    @plaid_provider.expects(:get_item_accounts).with(@plaid_item.access_token).returns(
      OpenStruct.new(accounts: [])
    )
    @snapshot.accounts
  end

  test "fetches transactions data if item supports transactions and any accounts present" do
    @plaid_item.update!(available_products: [ "transactions" ], billed_products: [])

    @snapshot.expects(:accounts).returns([
      OpenStruct.new(
        account_id: "123",
        type: "depository"
      )
    ]).at_least_once

    @plaid_provider.expects(:get_transactions).with(@plaid_item.access_token, next_cursor: nil).returns(
      OpenStruct.new(
        added: [],
        modified: [],
        removed: [],
        cursor: "test_cursor_1"
      )
    ).once
    @plaid_provider.expects(:get_item_investments).never
    @plaid_provider.expects(:get_item_liabilities).never

    @snapshot.get_account_data("123")
  end

  test "does not fetch transactions if no accounts" do
    @plaid_item.update!(available_products: [ "transactions" ], billed_products: [])

    @snapshot.expects(:accounts).returns([]).at_least_once

    @plaid_provider.expects(:get_transactions).never
    @plaid_provider.expects(:get_item_investments).never
    @plaid_provider.expects(:get_item_liabilities).never

    @snapshot.get_account_data("123")
  end

  test "updates next_cursor when fetching transactions" do
    @plaid_item.update!(available_products: [ "transactions" ], billed_products: [], next_cursor: "test_cursor_1")

    @snapshot.expects(:accounts).returns([
      OpenStruct.new(
        account_id: "123",
        type: "depository"
      )
    ]).at_least_once

    @plaid_provider.expects(:get_transactions).with(@plaid_item.access_token, next_cursor: "test_cursor_1").returns(
      OpenStruct.new(
        added: [],
        modified: [],
        removed: [],
        cursor: "test_cursor_2"
      )
    ).once

    @plaid_provider.expects(:get_item_investments).never
    @plaid_provider.expects(:get_item_liabilities).never

    @snapshot.get_account_data("123")
  end

  test "fetches investments data if item supports investments and investment accounts present" do
    @plaid_item.update!(available_products: [ "investments" ], billed_products: [])

    @snapshot.expects(:accounts).returns([
      OpenStruct.new(
        account_id: "123",
        type: "investment"
      )
    ]).at_least_once

    @plaid_provider.expects(:get_transactions).never
    @plaid_provider.expects(:get_item_investments).with(@plaid_item.access_token).once
    @plaid_provider.expects(:get_item_liabilities).never

    @snapshot.get_account_data("123")
  end

  test "does not fetch investments if no investment accounts" do
    @plaid_item.update!(available_products: [ "investments" ], billed_products: [])

    @snapshot.expects(:accounts).returns([]).at_least_once

    @plaid_provider.expects(:get_transactions).never
    @plaid_provider.expects(:get_item_investments).never
    @plaid_provider.expects(:get_item_liabilities).never

    @snapshot.get_account_data("123")
  end

  test "fetches liabilities data if item supports liabilities and liabilities accounts present" do
    @plaid_item.update!(available_products: [ "liabilities" ], billed_products: [])

    @snapshot.expects(:accounts).returns([
      OpenStruct.new(
        account_id: "123",
        type: "loan",
        subtype: "student"
      )
    ]).at_least_once

    @plaid_provider.expects(:get_transactions).never
    @plaid_provider.expects(:get_item_investments).never
    @plaid_provider.expects(:get_item_liabilities).with(@plaid_item.access_token).once

    @snapshot.get_account_data("123")
  end

  test "does not fetch liabilities if no liabilities accounts" do
    @plaid_item.update!(available_products: [ "liabilities" ], billed_products: [])

    @snapshot.expects(:accounts).returns([]).at_least_once

    @plaid_provider.expects(:get_transactions).never
    @plaid_provider.expects(:get_item_investments).never
    @plaid_provider.expects(:get_item_liabilities).never

    @snapshot.get_account_data("123")
  end

  test "records and skips liabilities when Plaid reports missing consent" do
    @plaid_item.update!(available_products: [ "transactions", "liabilities" ], billed_products: [])

    @snapshot.expects(:accounts).returns([
      OpenStruct.new(account_id: "123", type: "credit")
    ]).at_least_once

    @plaid_provider.expects(:get_transactions).with(@plaid_item.access_token, next_cursor: nil).returns(
      OpenStruct.new(added: [], modified: [], removed: [], cursor: "test_cursor_1")
    )
    @plaid_provider.expects(:get_item_liabilities).with(@plaid_item.access_token).raises(
      plaid_error("ADDITIONAL_CONSENT_REQUIRED")
    )

    data = nil
    assert_difference -> { DebugLogEntry.count }, 1 do
      data = @snapshot.get_account_data("123")
    end

    assert_nil data.liabilities_data
    assert_not_nil data.transactions_data

    flag = @plaid_item.reload.unavailable_products["liabilities"]
    assert_equal "ADDITIONAL_CONSENT_REQUIRED", flag["error_code"]
    assert_equal false, flag["retryable"]

    entry = DebugLogEntry.order(:created_at).last
    assert_equal "warn", entry.level
    assert_equal "provider_sync", entry.category
    assert_equal "liabilities", entry.metadata["product"]
    assert_equal @plaid_item.id, entry.metadata["plaid_item_id"]
  end

  test "records and skips investments when the product is not supported" do
    @plaid_item.update!(available_products: [ "investments" ], billed_products: [])

    @snapshot.expects(:accounts).returns([
      OpenStruct.new(account_id: "123", type: "investment")
    ]).at_least_once

    @plaid_provider.expects(:get_item_investments).with(@plaid_item.access_token).raises(
      plaid_error("PRODUCTS_NOT_SUPPORTED")
    )

    data = nil
    assert_difference -> { DebugLogEntry.count }, 1 do
      data = @snapshot.get_account_data("123")
    end

    assert_nil data.investments_data
    flag = @plaid_item.reload.unavailable_products["investments"]
    assert_equal "PRODUCTS_NOT_SUPPORTED", flag["error_code"]
    assert_equal false, flag["retryable"]
  end

  test "marks PRODUCT_NOT_READY as retryable so the next sync re-attempts it" do
    @plaid_item.update!(available_products: [ "liabilities" ], billed_products: [])

    @snapshot.expects(:accounts).returns([
      OpenStruct.new(account_id: "123", type: "loan", subtype: "student")
    ]).at_least_once

    @plaid_provider.expects(:get_item_liabilities).with(@plaid_item.access_token).raises(
      plaid_error("PRODUCT_NOT_READY", type: "API_ERROR")
    )

    @snapshot.get_account_data("123")

    flag = @plaid_item.reload.unavailable_products["liabilities"]
    assert_equal "PRODUCT_NOT_READY", flag["error_code"]
    assert_equal true, flag["retryable"]
    assert_includes @plaid_item.retryable_unavailable_product_names, "liabilities"
    assert_not_includes @plaid_item.declined_unavailable_product_names, "liabilities"
  end

  test "non-product Plaid errors on optional products still raise" do
    @plaid_item.update!(available_products: [ "liabilities" ], billed_products: [])

    @snapshot.expects(:accounts).returns([
      OpenStruct.new(account_id: "123", type: "loan", subtype: "student")
    ]).at_least_once

    @plaid_provider.expects(:get_item_liabilities).with(@plaid_item.access_token).raises(
      plaid_error("INTERNAL_SERVER_ERROR", type: "API_ERROR")
    )

    assert_raises(Plaid::ApiError) { @snapshot.get_account_data("123") }
    assert_empty @plaid_item.reload.unavailable_products
  end

  test "a tolerated product failure is only fetched once across accounts" do
    @plaid_item.update!(available_products: [ "liabilities" ], billed_products: [])

    @snapshot.expects(:accounts).returns([
      OpenStruct.new(account_id: "a1", type: "loan", subtype: "student"),
      OpenStruct.new(account_id: "a2", type: "loan", subtype: "student")
    ]).at_least_once

    @plaid_provider.expects(:get_item_liabilities).with(@plaid_item.access_token).once.raises(
      plaid_error("ADDITIONAL_CONSENT_REQUIRED")
    )

    assert_difference -> { DebugLogEntry.count }, 1 do
      @snapshot.get_account_data("a1")
      @snapshot.get_account_data("a2")
    end
  end

  test "consent error on the core transactions product raises a reconnect error" do
    @plaid_item.update!(available_products: [ "transactions" ], billed_products: [])

    @snapshot.expects(:accounts).returns([
      OpenStruct.new(account_id: "123", type: "depository")
    ]).at_least_once

    @plaid_provider.expects(:get_transactions).with(@plaid_item.access_token, next_cursor: nil).raises(
      plaid_error("ADDITIONAL_CONSENT_REQUIRED")
    )

    error = assert_raises(PlaidItem::ConsentRequiredError) { @snapshot.get_account_data("123") }
    assert_equal "transactions", error.product
    assert_equal "ADDITIONAL_CONSENT_REQUIRED", error.error_code
    assert_match(/reconnect/i, error.message)
    assert_match(/transactions/i, error.message)
  end

  private

    def plaid_error(error_code, type: "INVALID_INPUT", message: "Plaid error")
      Plaid::ApiError.new(
        code: 400,
        response_body: {
          "error_type" => type,
          "error_code" => error_code,
          "error_message" => message
        }.to_json
      )
    end
end
