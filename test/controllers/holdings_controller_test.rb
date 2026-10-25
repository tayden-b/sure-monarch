require "test_helper"

class HoldingsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in users(:family_admin)
    @account = accounts(:investment)
    @holding = @account.holdings.first
  end

  test "gets holdings" do
    get holdings_url(account_id: @account.id)
    assert_response :success
  end

  test "gets family holdings page with an aggregate row per security" do
    second_account = @account.family.accounts.create!(
      name: "Second Brokerage", balance: 500, currency: @account.currency,
      accountable: Investment.new
    )

    Holding.create!(
      account: second_account, security: @holding.security, date: Date.current,
      qty: 5, price: @holding.price, amount: 5 * @holding.price, currency: @account.currency
    )

    get holdings_url

    assert_response :success
    assert_match(/#{Regexp.escape(@holding.security.ticker)}/, response.body)
    # the same security rolls up into one row that reports both accounts
    assert_match(/2 accounts/, response.body)
  end

  test "family holdings page hides securities only held in excluded accounts" do
    excluded_security = securities(:msft)
    excluded_account = @account.family.accounts.create!(
      name: "Excluded", balance: 500, currency: "USD",
      exclude_from_reports: true, accountable: Investment.new
    )

    Holding.create!(
      account: excluded_account, security: excluded_security, date: Date.current,
      qty: 5, price: 100, amount: 500, currency: "USD"
    )

    get holdings_url

    assert_response :success
    assert_no_match(/#{Regexp.escape(excluded_security.ticker)}/, response.body)
  end

  test "gets per-security drill-down across accounts" do
    get security_holdings_url(security_id: @holding.security.id)

    assert_response :success
    assert_select "h3", text: @holding.security.name
  end

  test "drill-down is not found for a security the family does not hold" do
    foreign_security = securities(:msft)

    get security_holdings_url(security_id: foreign_security.id)

    assert_response :not_found
  end

  test "gets holding" do
    get holding_path(@holding)

    assert_response :success
  end

  test "shows exact share count without rounding" do
    @holding.update!(qty: 10.374)

    get holding_path(@holding)

    assert_select "##{dom_id(@holding, :shares)}", text: "10.374"
  end

  test "shows the exact stored quantity for a small crypto holding in the holdings list" do
    account = accounts(:crypto)
    security = Security.create!(
      ticker: "CRYPTO:BTC",
      name: "Bitcoin",
      exchange_operating_mic: "XCBS",
      offline: true
    )
    holding = account.holdings.create!(
      security: security,
      date: Date.current,
      qty: BigDecimal("0.000000000000000148"),
      price: 100_000,
      amount: 14.884,
      currency: "USD"
    )

    get holdings_url(account_id: account.id)

    assert_select "##{dom_id(holding)} p", text: "0.000000000000000148 shares"
  end

  test "destroys holding and associated entries" do
    assert_difference -> { Holding.count } => -1,
                      -> { Entry.count } => -1 do
      delete holding_path(@holding)
    end

    assert_redirected_to account_path(@holding.account)
    assert_empty @holding.account.entries.where(entryable: @holding.account.trades.where(security: @holding.security))
  end

  test "updates cost basis with total amount divided by qty" do
    # Given: holding with 10 shares
    @holding.update!(qty: 10, cost_basis: nil, cost_basis_source: nil, cost_basis_locked: false)

    # When: user submits total cost basis of $100 (should become $10 per share)
    patch holding_path(@holding), params: { holding: { cost_basis: "100.00" } }

    # Redirects to account page holdings tab to refresh list
    assert_redirected_to account_path(@holding.account, tab: "holdings")
    @holding.reload

    # Then: cost_basis should be per-share ($10), not total
    assert_equal 10.0, @holding.cost_basis.to_f
    assert_equal "manual", @holding.cost_basis_source
    assert @holding.cost_basis_locked?
  end

  test "unlock_cost_basis removes lock" do
    # Given: locked holding
    @holding.update!(cost_basis: 50.0, cost_basis_source: "manual", cost_basis_locked: true)

    # When: user unlocks
    post unlock_cost_basis_holding_path(@holding)

    # Redirects to account page holdings tab to refresh list
    assert_redirected_to account_path(@holding.account, tab: "holdings")
    @holding.reload

    # Then: lock is removed but cost_basis and source remain
    assert_not @holding.cost_basis_locked?
    assert_equal 50.0, @holding.cost_basis.to_f
    assert_equal "manual", @holding.cost_basis_source
  end

  test "remap_security brings offline security back online" do
    # Given: the target security is marked offline (e.g. created by a failed QIF import)
    msft = securities(:msft)
    msft.update!(offline: true, failed_fetch_count: 3)

    # When: user explicitly selects it from the provider search and saves
    patch remap_security_holding_path(@holding), params: { security_id: "MSFT|XNAS" }

    # Then: the security is brought back online and the holding is remapped
    assert_redirected_to account_path(@holding.account, tab: "holdings")
    @holding.reload
    msft.reload
    assert_equal msft.id, @holding.security_id
    assert_not msft.offline?
    assert_equal 0, msft.failed_fetch_count
  end

  test "sync_prices redirects with alert for offline security" do
    @holding.security.update!(offline: true)

    post sync_prices_holding_path(@holding)

    assert_redirected_to account_path(@holding.account, tab: "holdings")
    assert_equal I18n.t("holdings.sync_prices.unavailable"), flash[:alert]
  end

  test "sync_prices syncs market data and redirects with notice" do
    Security.any_instance.expects(:import_provider_prices).with(
      start_date: 31.days.ago.to_date,
      end_date: Date.current,
      clear_cache: true
    ).returns([ 31, nil ])
    Security.any_instance.stubs(:import_provider_details)
    materializer = mock("materializer")
    materializer.expects(:materialize_balances).once
    Balance::Materializer.expects(:new).with(
      @holding.account,
      strategy: :forward,
      security_ids: [ @holding.security_id ]
    ).returns(materializer)

    post sync_prices_holding_path(@holding)

    assert_redirected_to account_path(@holding.account, tab: "holdings")
    assert_equal I18n.t("holdings.sync_prices.success"), flash[:notice]
  end

  test "sync_prices shows provider error inline when provider returns no prices" do
    Security.any_instance.stubs(:import_provider_prices).returns([ 0, "Yahoo Finance rate limit exceeded" ])
    Security.any_instance.stubs(:import_provider_details)

    post sync_prices_holding_path(@holding)

    assert_redirected_to account_path(@holding.account, tab: "holdings")
    assert_equal "Yahoo Finance rate limit exceeded", flash[:alert]
  end
end
