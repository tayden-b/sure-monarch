require "test_helper"

class AccountProvider::ReattachTest < ActiveSupport::TestCase
  include EntriesTestHelper

  setup do
    @family = families(:dylan_family)
    @target = accounts(:depository)
    @shell = @family.accounts.create!(
      name: "Plaid Depository Account",
      accountable: Depository.new(subtype: "checking"),
      balance: 100,
      cash_balance: 100,
      currency: "USD"
    )
    @plaid_account = PlaidAccount.create!(
      plaid_item: plaid_items(:one),
      name: "Plaid Checking",
      plaid_id: "reattach_pa_1",
      plaid_type: "depository",
      plaid_subtype: "checking",
      currency: "USD",
      current_balance: 100
    )
    @link = AccountProvider.create!(account: @shell, provider: @plaid_account, provider_type: "PlaidAccount")
  end

  test "reattachable? is true for a provider-created shell" do
    create_transaction(account: @shell, name: "PAID BY PLAID", source: "plaid", external_id: "p-1")
    create_valuation(account: @shell, kind: "current_anchor", name: "Current balance")

    assert AccountProvider::Reattach.reattachable?(@link)
  end

  test "reattachable? is false when the account carries non-provider entries" do
    create_transaction(account: @shell, name: "SOMETHING ELSE", source: "simplefin", external_id: "s-1")
    refute AccountProvider::Reattach.reattachable?(@link)

    @shell.entries.destroy_all
    create_transaction(account: @shell, name: "HAND ENTERED", source: nil)
    refute AccountProvider::Reattach.reattachable?(@link)
  end

  test "reattachable? is false when the account has a Monarch mapping" do
    MonarchSourceMapping.create!(
      family: @family, collection: "accounts", monarch_id: "m-1", record: @shell, payload: {}
    )

    refute AccountProvider::Reattach.reattachable?(@link)
  end

  test "call moves the link, entries, holdings and anchors to the target and deletes the shell" do
    txn = create_transaction(account: @shell, name: "PAID BY PLAID", source: "plaid", external_id: "p-1")
    anchor = create_valuation(account: @shell, kind: "current_anchor", name: "Current balance", amount: 100)
    holding = @shell.holdings.create!(
      security: securities(:aapl), account_provider: @link,
      qty: 1, price: 10, amount: 10, currency: "USD", date: Date.current
    )

    AccountProvider::Reattach.new(account_provider: @link, target_account: @target).call

    assert_equal @target, @link.reload.account
    assert_equal @target, txn.reload.account
    assert_equal @target, anchor.reload.account
    assert_equal @target, holding.reload.account
    assert_equal "pending_deletion", @shell.reload.status
  end

  test "call refuses when the target already has a provider of the same type" do
    other = PlaidAccount.create!(
      plaid_item: plaid_items(:one),
      name: "Other Plaid Account",
      plaid_id: "reattach_pa_2",
      plaid_type: "depository",
      plaid_subtype: "checking",
      currency: "USD",
      current_balance: 50
    )
    AccountProvider.create!(account: @target, provider: other, provider_type: "PlaidAccount")

    error = assert_raises(AccountProvider::Reattach::Error) do
      AccountProvider::Reattach.new(account_provider: @link, target_account: @target).call
    end
    assert_match(/already has a PlaidAccount provider link/, error.message)

    # Nothing moved
    assert_equal @shell, @link.reload.account
    assert_equal "active", @shell.reload.status
  end

  test "call refuses when the provider feed's accountable class differs from the target" do
    @plaid_account.update!(plaid_type: "credit", plaid_subtype: "credit card")

    error = assert_raises(AccountProvider::Reattach::Error) do
      AccountProvider::Reattach.new(account_provider: @link, target_account: @target).call
    end
    assert_match(/Cannot attach a PlaidAccount feed to a Depository account/, error.message)

    # Nothing moved — the depository shell survives to be reattachable later
    assert_equal @shell, @link.reload.account
    assert_equal "active", @shell.reload.status
  end

  test "call allows a depository feed onto a depository target" do
    AccountProvider::Reattach.new(account_provider: @link, target_account: @target).call

    assert_equal @target, @link.reload.account
  end

  test "call refuses a kraken feed onto a depository target" do
    crypto_shell = @family.accounts.create!(
      name: "Kraken Shell", accountable: Crypto.new, balance: 0, currency: "USD"
    )
    link = AccountProvider.create!(account: crypto_shell, provider: kraken_accounts(:one), provider_type: "KrakenAccount")

    assert_raises(AccountProvider::Reattach::Error) do
      AccountProvider::Reattach.new(account_provider: link, target_account: @target).call
    end
  end

  test "call refuses a target in another family" do
    foreign = families(:empty).accounts.create!(
      name: "Foreign", accountable: Depository.new, balance: 0, currency: "USD"
    )

    assert_raises(AccountProvider::Reattach::Error) do
      AccountProvider::Reattach.new(account_provider: @link, target_account: foreign).call
    end
  end

  test "call refuses a shell carrying non-provider data" do
    create_transaction(account: @shell, name: "HAND ENTERED", source: nil)

    assert_raises(AccountProvider::Reattach::Error) do
      AccountProvider::Reattach.new(account_provider: @link, target_account: @target).call
    end
  end
end
