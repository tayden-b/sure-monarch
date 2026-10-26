require "test_helper"

class PlaidAccount::ProcessorTest < ActiveSupport::TestCase
  setup do
    @plaid_account = plaid_accounts(:one)
  end

  test "processes new account and assigns attributes" do
    Account.destroy_all # Clear out internal accounts so we start fresh

    expect_default_subprocessor_calls

    @plaid_account.update!(
      plaid_id: "test_plaid_id",
      plaid_type: "depository",
      plaid_subtype: "checking",
      current_balance: 1000,
      available_balance: 1000,
      currency: "USD",
      name: "Test Plaid Account",
      mask: "1234"
    )

    assert_difference "Account.count" do
      PlaidAccount::Processor.new(@plaid_account).process
    end

    @plaid_account.reload

    account = Account.order(created_at: :desc).first
    assert_equal "Test Plaid Account", account.name
    assert_equal "checking", account.subtype
    assert_equal 1000, account.balance
    assert_equal 1000, account.cash_balance
    assert_equal "USD", account.currency
    assert_equal "Depository", account.accountable_type
    assert_equal "checking", account.subtype

    # Verify AccountProvider was created
    assert account.linked?
    assert_equal 1, account.account_providers.count
    assert_equal @plaid_account.id, account.account_providers.first.provider_id
    assert_equal "PlaidAccount", account.account_providers.first.provider_type
  end

  test "a new account inherits the owner of the item that produced it" do
    # Accounts are created inside the sync job, where Current.user is nil. If
    # the owner were left to Account#assign_default_owner it would fall back to
    # the family's first admin, quietly taking a member's own connection away
    # from them (issue #3579).
    Account.destroy_all
    member = users(:family_member)
    @plaid_account.plaid_item.update!(owner: member)

    expect_default_subprocessor_calls

    Current.reset

    assert_difference "Account.count" do
      PlaidAccount::Processor.new(@plaid_account).process
    end

    assert_equal member, Account.order(created_at: :desc).first.owner
  end

  test "processing is idempotent with updates and enrichments" do
    expect_default_subprocessor_calls

    assert_equal "Plaid Depository Account", @plaid_account.current_account.name
    assert_equal "checking", @plaid_account.current_account.subtype

    @plaid_account.current_account.update!(
      name: "User updated name",
      balance: 2000 # User cannot override balance.  This will be overridden by the processor on next processing
    )

    @plaid_account.current_account.accountable.update!(subtype: "savings")

    @plaid_account.current_account.lock_attr!(:name)
    @plaid_account.current_account.accountable.lock_attr!(:subtype)
    @plaid_account.current_account.lock_attr!(:balance) # Even if balance somehow becomes locked, Plaid ignores it and overrides it

    assert_no_difference "Account.count" do
      PlaidAccount::Processor.new(@plaid_account).process
    end

    @plaid_account.reload

    assert_equal "User updated name", @plaid_account.current_account.name
    assert_equal "savings", @plaid_account.current_account.subtype
    assert_equal @plaid_account.current_balance, @plaid_account.current_account.balance # Overriden by processor
  end

  test "account processing failure halts further processing" do
    Account.any_instance.stubs(:save!).raises(StandardError.new("Test error"))

    PlaidAccount::Transactions::Processor.any_instance.expects(:process).never
    PlaidAccount::Investments::TransactionsProcessor.any_instance.expects(:process).never
    PlaidAccount::Investments::HoldingsProcessor.any_instance.expects(:process).never

    expect_no_investment_balance_calculator_calls
    expect_no_liability_processor_calls

    assert_raises(StandardError) do
      PlaidAccount::Processor.new(@plaid_account).process
    end
  end

  test "product processing failure reports exception and continues processing" do
    PlaidAccount::Transactions::Processor.any_instance.stubs(:process).raises(StandardError.new("Test error"))

    # Subsequent product processors still run
    expect_investment_product_processor_calls

    assert_nothing_raised do
      PlaidAccount::Processor.new(@plaid_account).process
    end
  end

  test "calculates balance using BalanceCalculator for investment accounts" do
    @plaid_account.update!(plaid_type: "investment")

    # Balance is called twice: once for account.balance and once for set_current_balance
    PlaidAccount::Investments::BalanceCalculator.any_instance.expects(:balance).returns(1000).twice
    PlaidAccount::Investments::BalanceCalculator.any_instance.expects(:cash_balance).returns(1000).once

    PlaidAccount::Processor.new(@plaid_account).process

    # Verify that the balance was set correctly
    account = @plaid_account.current_account
    assert_equal 1000, account.balance
    assert_equal 1000, account.cash_balance

    # Verify current balance anchor was created with correct value
    current_anchor = account.valuations.current_anchor.first
    assert_not_nil current_anchor
    assert_equal 1000, current_anchor.entry.amount
  end

  test "processes credit liability data" do
    expect_investment_product_processor_calls
    expect_no_investment_balance_calculator_calls
    expect_depository_product_processor_calls

    @plaid_account.update!(plaid_type: "credit", plaid_subtype: "credit card")

    PlaidAccount::Liabilities::CreditProcessor.any_instance.expects(:process).once
    PlaidAccount::Liabilities::MortgageProcessor.any_instance.expects(:process).never
    PlaidAccount::Liabilities::StudentLoanProcessor.any_instance.expects(:process).never

    PlaidAccount::Processor.new(@plaid_account).process
  end

  test "processes credit liability data for non-credit-card subtypes" do
    # Plaid reports PayPal Credit as credit/paypal. Dispatching only on
    # ["credit", "credit card"] left these accounts with a stored liabilities
    # payload but no minimum_payment or apr.
    expect_investment_product_processor_calls
    expect_no_investment_balance_calculator_calls
    expect_depository_product_processor_calls

    @plaid_account.update!(plaid_type: "credit", plaid_subtype: "paypal")

    PlaidAccount::Liabilities::CreditProcessor.any_instance.expects(:process).once
    PlaidAccount::Liabilities::MortgageProcessor.any_instance.expects(:process).never
    PlaidAccount::Liabilities::StudentLoanProcessor.any_instance.expects(:process).never

    PlaidAccount::Processor.new(@plaid_account).process
  end

  test "processes mortgage liability data" do
    expect_investment_product_processor_calls
    expect_no_investment_balance_calculator_calls
    expect_depository_product_processor_calls

    @plaid_account.update!(plaid_type: "loan", plaid_subtype: "mortgage")

    PlaidAccount::Liabilities::CreditProcessor.any_instance.expects(:process).never
    PlaidAccount::Liabilities::MortgageProcessor.any_instance.expects(:process).once
    PlaidAccount::Liabilities::StudentLoanProcessor.any_instance.expects(:process).never

    PlaidAccount::Processor.new(@plaid_account).process
  end

  test "processes student loan liability data" do
    expect_investment_product_processor_calls
    expect_no_investment_balance_calculator_calls
    expect_depository_product_processor_calls

    @plaid_account.update!(plaid_type: "loan", plaid_subtype: "student")

    PlaidAccount::Liabilities::CreditProcessor.any_instance.expects(:process).never
    PlaidAccount::Liabilities::MortgageProcessor.any_instance.expects(:process).never
    PlaidAccount::Liabilities::StudentLoanProcessor.any_instance.expects(:process).once

    PlaidAccount::Processor.new(@plaid_account).process
  end

  test "creates current balance anchor when processing account" do
    expect_default_subprocessor_calls

    # Clear out accounts to start fresh
    Account.destroy_all

    @plaid_account.update!(
      plaid_id: "test_plaid_id",
      plaid_type: "depository",
      plaid_subtype: "checking",
      current_balance: 1500,
      available_balance: 1500,
      currency: "USD",
      name: "Test Account with Anchor",
      mask: "1234"
    )

    assert_difference "Account.count", 1 do
      assert_difference "Entry.count", 1 do
        assert_difference "Valuation.count", 1 do
          PlaidAccount::Processor.new(@plaid_account).process
        end
      end
    end

    account = Account.order(created_at: :desc).first
    assert_equal 1500, account.balance

    # Verify current balance anchor was created
    current_anchor = account.valuations.current_anchor.first
    assert_not_nil current_anchor
    assert_equal "current_anchor", current_anchor.kind
    assert_equal 1500, current_anchor.entry.amount
    assert_equal Date.current, current_anchor.entry.date
    assert_equal "Current balance", current_anchor.entry.name
  end

  test "updates existing current balance anchor when reprocessing" do
    # First process creates the account and anchor
    expect_default_subprocessor_calls
    PlaidAccount::Processor.new(@plaid_account).process

    account = @plaid_account.current_account
    original_anchor = account.valuations.current_anchor.first
    assert_not_nil original_anchor
    original_anchor_id = original_anchor.id
    original_entry_id = original_anchor.entry.id
    original_balance = original_anchor.entry.amount

    # Update the plaid account balance
    @plaid_account.update!(current_balance: 2500)

    # Expect subprocessor calls again for the second processing
    expect_default_subprocessor_calls

    # Reprocess should update the existing anchor
    assert_no_difference "Valuation.count" do
      assert_no_difference "Entry.count" do
        PlaidAccount::Processor.new(@plaid_account).process
      end
    end

    # Verify the anchor was updated
    original_anchor.reload
    assert_equal original_anchor_id, original_anchor.id
    assert_equal original_entry_id, original_anchor.entry.id
    assert_equal 2500, original_anchor.entry.amount
    assert_not_equal original_balance, original_anchor.entry.amount
  end

  # --- auto-attach to imported (Monarch) accounts --------------------------
  #
  # A first sync must attach the Plaid feed to the imported account it
  # matches instead of creating a duplicate beside it. See
  # AccountProvider::ImportMatcher for the matching rules.

  test "attaches to the imported account whose name carries the mask" do
    Account.destroy_all
    imported = import_account(name: "TOTAL CHECKING (...1899)", accountable: Depository.new(subtype: "checking"))
    plaid_account = build_unlinked_plaid_account(mask: "1899")

    expect_default_subprocessor_calls

    assert_no_difference "Account.count" do
      assert_difference "AccountProvider.count", 1 do
        PlaidAccount::Processor.new(plaid_account).process
      end
    end

    imported.reload
    assert_equal "TOTAL CHECKING (...1899)", imported.name
    assert_equal plaid_account.id, imported.account_providers.first.provider_id
    assert_equal 1000, imported.balance
    assert_equal plaid_account.current_account, imported
  end

  test "attaches by Monarch payload mask when the name does not carry it" do
    Account.destroy_all
    imported = import_account(name: "My Chase Checking", accountable: Depository.new(subtype: "checking"), mask: "1899")
    plaid_account = build_unlinked_plaid_account(mask: "1899")

    expect_default_subprocessor_calls

    assert_no_difference "Account.count" do
      PlaidAccount::Processor.new(plaid_account).process
    end

    assert_equal imported, plaid_account.current_account
  end

  test "attaches by plaid institution when the match is unique" do
    Account.destroy_all
    @plaid_account.plaid_item.update!(institution_id: "ins_127991")
    imported = import_account(
      name: "Chase Savings",
      accountable: Depository.new(subtype: "savings"),
      plaid_institution_id: "ins_127991"
    )
    plaid_account = build_unlinked_plaid_account(mask: "0000")

    expect_default_subprocessor_calls

    assert_no_difference "Account.count" do
      PlaidAccount::Processor.new(plaid_account).process
    end

    assert_equal imported, plaid_account.current_account
  end

  test "creates a new account when two candidates could match" do
    Account.destroy_all
    @plaid_account.plaid_item.update!(institution_id: "ins_127991")
    import_account(name: "Chase Checking 1", accountable: Depository.new, plaid_institution_id: "ins_127991")
    import_account(name: "Chase Checking 2", accountable: Depository.new, plaid_institution_id: "ins_127991")
    plaid_account = build_unlinked_plaid_account(mask: "0000")

    expect_default_subprocessor_calls

    assert_difference "Account.count", 1 do
      PlaidAccount::Processor.new(plaid_account).process
    end
  end

  test "creates a new account when nothing matches" do
    Account.destroy_all
    import_account(name: "TOTAL CHECKING (...1899)", accountable: Depository.new)
    plaid_account = build_unlinked_plaid_account(mask: "9999")

    expect_default_subprocessor_calls

    assert_difference "Account.count", 1 do
      PlaidAccount::Processor.new(plaid_account).process
    end
  end

  test "does not attach to a disabled imported account" do
    Account.destroy_all
    imported = import_account(name: "TOTAL CHECKING (...1899)", accountable: Depository.new)
    imported.disable!
    plaid_account = build_unlinked_plaid_account(mask: "1899")

    expect_default_subprocessor_calls

    assert_difference "Account.count", 1 do
      PlaidAccount::Processor.new(plaid_account).process
    end
  end

  test "investment attach anchors Plaid balance without double-counting holdings" do
    Account.destroy_all
    Holding.destroy_all

    imported = import_account(
      name: "Individual - TOD (...7633)",
      accountable: Investment.new(subtype: "brokerage"),
      mask: "7633"
    )

    # A Monarch holding imported at the archive date
    security = securities(:aapl)
    imported.holdings.create!(security: security, qty: 10, price: 150, amount: 1500, currency: "USD", date: 30.days.ago.to_date)

    plaid_account = build_unlinked_plaid_account(plaid_type: "investment", mask: "7633")

    PlaidAccount::Transactions::Processor.any_instance.expects(:process).once
    PlaidAccount::Investments::TransactionsProcessor.any_instance.expects(:process).once
    PlaidAccount::Investments::HoldingsProcessor.any_instance.expects(:process).once
    PlaidAccount::Investments::BalanceCalculator.any_instance.expects(:balance).returns(2000).twice
    PlaidAccount::Investments::BalanceCalculator.any_instance.expects(:cash_balance).returns(500).once

    assert_no_difference "Account.count" do
      PlaidAccount::Processor.new(plaid_account).process
    end

    imported.reload
    assert_equal imported, plaid_account.current_account
    assert_equal 2000, imported.balance
    assert_equal 2000, imported.valuations.current_anchor.first.entry.amount

    # The imported Monarch holding is still there, alone — Plaid's holdings
    # processor is mocked out, so no duplicate was written by the attach.
    assert_equal 1, imported.holdings.count
  end

  private
    def build_unlinked_plaid_account(overrides = {})
      PlaidAccount.create!({
        plaid_item: @plaid_account.plaid_item,
        name: "TOTAL CHECKING",
        plaid_id: "plaid_attach_#{SecureRandom.hex(4)}",
        plaid_type: "depository",
        plaid_subtype: "checking",
        currency: "USD",
        current_balance: 1000,
        available_balance: 1000
      }.merge(overrides))
    end

    def import_account(name:, accountable:, mask: nil, plaid_institution_id: nil, institution_name: "Chase")
      account = families(:dylan_family).accounts.create!(
        name: name,
        accountable: accountable,
        balance: 0,
        cash_balance: 0,
        currency: "USD",
        locked_attributes: { "name" => Time.current }
      )
      MonarchSourceMapping.create!(
        family: families(:dylan_family),
        collection: "accounts",
        monarch_id: SecureRandom.uuid,
        record: account,
        payload: {
          "mask" => mask,
          "institution" => { "name" => institution_name, "plaidInstitutionId" => plaid_institution_id },
          "type" => { "name" => "depository" },
          "subtype" => { "name" => "checking" }
        }
      )
      account
    end

    def expect_investment_product_processor_calls
      PlaidAccount::Investments::TransactionsProcessor.any_instance.expects(:process).once
      PlaidAccount::Investments::HoldingsProcessor.any_instance.expects(:process).once
    end

    def expect_depository_product_processor_calls
      PlaidAccount::Transactions::Processor.any_instance.expects(:process).once
    end

    def expect_no_investment_balance_calculator_calls
      PlaidAccount::Investments::BalanceCalculator.any_instance.expects(:balance).never
      PlaidAccount::Investments::BalanceCalculator.any_instance.expects(:cash_balance).never
    end

    def expect_no_liability_processor_calls
      PlaidAccount::Liabilities::CreditProcessor.any_instance.expects(:process).never
      PlaidAccount::Liabilities::MortgageProcessor.any_instance.expects(:process).never
      PlaidAccount::Liabilities::StudentLoanProcessor.any_instance.expects(:process).never
    end

    def expect_default_subprocessor_calls
      expect_depository_product_processor_calls
      expect_investment_product_processor_calls
      expect_no_investment_balance_calculator_calls
      expect_no_liability_processor_calls
    end
end
