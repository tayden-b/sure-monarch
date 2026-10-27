# All Plaid data is fetched at the item-level.  This class is a simple wrapper that
# providers a convenience method, get_account_data which scopes the item-level payload
# to each Plaid Account
class PlaidItem::AccountsSnapshot
  # Plaid error_codes meaning "this product's data isn't available on this
  # item": the user declined to share it during Link
  # (ADDITIONAL_CONSENT_REQUIRED, ACCESS_NOT_GRANTED), the institution can't
  # serve it (PRODUCTS_NOT_SUPPORTED), no matching accounts exist
  # (NO_LIABILITY_ACCOUNTS, NO_INVESTMENT_ACCOUNTS), or Plaid is still
  # preparing it (PRODUCT_NOT_READY). On optional products the fetch degrades
  # to nil instead of failing the whole item sync.
  OPTIONAL_PRODUCT_ERROR_CODES = %w[
    ADDITIONAL_CONSENT_REQUIRED
    ACCESS_NOT_GRANTED
    PRODUCTS_NOT_SUPPORTED
    PRODUCT_NOT_READY
    NO_LIABILITY_ACCOUNTS
    NO_INVESTMENT_ACCOUNTS
  ].freeze

  # Codes Plaid resolves without user action — the product is re-attempted on
  # the next scheduled sync rather than treated as permanently declined.
  RETRYABLE_PRODUCT_ERROR_CODES = %w[PRODUCT_NOT_READY].freeze

  # Consent-class errors on core products (transactions) still fail the sync,
  # but get a human-readable message telling the user to reconnect and grant
  # access.
  CORE_CONSENT_ERROR_CODES = %w[ADDITIONAL_CONSENT_REQUIRED ACCESS_NOT_GRANTED].freeze

  def initialize(plaid_item, plaid_provider:)
    @plaid_item = plaid_item
    @plaid_provider = plaid_provider
  end

  def accounts
    @accounts ||= plaid_provider.get_item_accounts(plaid_item.access_token).accounts
  end

  def get_account_data(account_id)
    AccountData.new(
      account_data: accounts.find { |a| a.account_id == account_id },
      transactions_data: account_scoped_transactions_data(account_id),
      investments_data: account_scoped_investments_data(account_id),
      liabilities_data: account_scoped_liabilities_data(account_id)
    )
  end

  def transactions_cursor
    return nil unless transactions_data
    transactions_data.cursor
  end

  private
    attr_reader :plaid_item, :plaid_provider

    TransactionsData = Data.define(:added, :modified, :removed)
    LiabilitiesData = Data.define(:credit, :mortgage, :student)
    InvestmentsData = Data.define(:transactions, :holdings, :securities)
    AccountData = Data.define(:account_data, :transactions_data, :investments_data, :liabilities_data)

    def account_scoped_transactions_data(account_id)
      return nil unless transactions_data

      TransactionsData.new(
        added: transactions_data.added.select { |t| t.account_id == account_id },
        modified: transactions_data.modified.select { |t| t.account_id == account_id },
        removed: transactions_data.removed.select { |t| t.account_id == account_id }
      )
    end

    def account_scoped_investments_data(account_id)
      return nil unless investments_data

      transactions = investments_data.transactions.select { |t| t.account_id == account_id }
      holdings = investments_data.holdings.select { |h| h.account_id == account_id }
      securities = transactions.count > 0 && holdings.count > 0 ? investments_data.securities : []

      InvestmentsData.new(
        transactions: transactions,
        holdings: holdings,
        securities: securities
      )
    end

    def account_scoped_liabilities_data(account_id)
      return nil unless liabilities_data

      LiabilitiesData.new(
        credit: liabilities_data.credit&.find { |c| c.account_id == account_id },
        mortgage: liabilities_data.mortgage&.find { |m| m.account_id == account_id },
        student: liabilities_data.student&.find { |s| s.account_id == account_id }
      )
    end

    def can_fetch_transactions?
      plaid_item.supports_product?("transactions") && accounts.any?
    end

    def transactions_data
      return nil unless can_fetch_transactions?

      @transactions_data ||= begin
        plaid_provider.get_transactions(
          plaid_item.access_token,
          next_cursor: plaid_item.next_cursor
        )
      rescue Plaid::ApiError => e
        if CORE_CONSENT_ERROR_CODES.include?(plaid_error_code(e))
          raise PlaidItem::ConsentRequiredError.new(
            product: "transactions",
            error_code: plaid_error_code(e),
            item_name: plaid_item.name
          )
        end
        raise
      end
    end

    def can_fetch_investments?
      plaid_item.supports_product?("investments") &&
      accounts.any? { |a| a.type == "investment" }
    end

    # `||=` can't memoize a tolerated failure (it resolves to nil), so the
    # fetch-attempt flag is tracked separately: one provider call, one debug
    # log entry and one item flag per sync no matter how many accounts read it.
    def investments_data
      return nil unless can_fetch_investments?

      unless @investments_data_attempted
        @investments_data_attempted = true
        @investments_data = fetch_optional_product("investments") do
          plaid_provider.get_item_investments(plaid_item.access_token)
        end
      end

      @investments_data
    end

    def can_fetch_liabilities?
      plaid_item.supports_product?("liabilities") &&
      accounts.any? do |a|
        # Plaid's `credit` type has two subtypes: "credit card" and "paypal".
        # Liabilities covers both, so match on the type rather than allow-listing
        # a single subtype -- otherwise a PayPal Credit account leaves
        # `liabilities` in billed_products (i.e. billed) but never fetched.
        a.type == "credit" ||
        a.type == "loan" && (a.subtype == "mortgage" || a.subtype == "student")
      end
    end

    def liabilities_data
      return nil unless can_fetch_liabilities?

      unless @liabilities_data_attempted
        @liabilities_data_attempted = true
        @liabilities_data = fetch_optional_product("liabilities") do
          plaid_provider.get_item_liabilities(plaid_item.access_token)
        end
      end

      @liabilities_data
    end

    # Optional products are independent of the core accounts/transactions
    # import: an OAuth user may decline (or an institution may not offer) one
    # product while the rest of the item syncs fine. Whitelisted "product not
    # available" errors are recorded on the item — surfacing the reconnect
    # notice in the UI — and logged for support; the fetch resolves to nil so
    # the rest of the sync proceeds. Anything else still fails the sync.
    def fetch_optional_product(product)
      yield
    rescue Plaid::ApiError => e
      raise unless optional_product_error?(e)

      record_unavailable_product(product, e)
      nil
    end

    def optional_product_error?(error)
      OPTIONAL_PRODUCT_ERROR_CODES.include?(plaid_error_code(error))
    end

    def record_unavailable_product(product, error)
      error_body = plaid_error_body(error)
      error_code = error_body["error_code"].to_s
      retryable = RETRYABLE_PRODUCT_ERROR_CODES.include?(error_code)

      plaid_item.record_unavailable_product!(product, error_code:, retryable:)

      DebugLogEntry.capture(
        category: "provider_sync",
        level: "warn",
        message: "Plaid product '#{product}' unavailable for item #{plaid_item.name}: #{error_code}",
        source: self.class.name,
        provider_key: "plaid",
        family: plaid_item.family,
        metadata: {
          plaid_item_id: plaid_item.id,
          institution_id: plaid_item.institution_id,
          product: product,
          error_code: error_code,
          error_type: error_body["error_type"],
          error_message: error_body["error_message"],
          retryable: retryable
        }
      )
    end

    def plaid_error_body(error)
      JSON.parse(error.response_body.to_s)
    rescue JSON::ParserError
      {}
    end

    def plaid_error_code(error)
      plaid_error_body(error)["error_code"].to_s
    end
end
