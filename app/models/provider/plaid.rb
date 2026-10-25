class Provider::Plaid
  attr_reader :client, :region

  SUPPORTED_PLAID_PRODUCTS = %w[transactions investments liabilities].freeze

  # Plaid caps `days_requested` at 730 — the absolute maximum history any
  # Item can backfill.
  MAX_HISTORY_DAYS = 730

  # How much transaction history to request on first link. Self-hosted users
  # get Plaid's maximum (730 days) by default; set PLAID_HISTORY_DAYS to
  # shrink the initial backfill (e.g. 90 to iterate faster in Sandbox).
  # Values above Plaid's 730-day cap are clamped.
  def self.max_history_days
    requested = ENV["PLAID_HISTORY_DAYS"].presence&.to_i
    return MAX_HISTORY_DAYS unless requested&.positive?

    [ requested, MAX_HISTORY_DAYS ].min
  end

  # Public origin Plaid can reach this instance at. A self-hosted instance is
  # often browsed on a private address (localhost, or the tailnet hostname via
  # Tailscale Serve) while Plaid-facing traffic (OAuth redirects, webhooks)
  # goes through a public URL such as Tailscale Funnel. APP_HOST records that
  # public origin; the older APP_DOMAIN is honoured too. Returns nil when
  # neither is set so callers fall back to the request-derived host.
  def self.app_base_url
    raw = ENV["APP_HOST"].presence || ENV["APP_DOMAIN"].presence
    return nil if raw.blank?

    raw = "https://#{raw}" unless raw.match?(%r{\Ahttps?://}i)
    raw.chomp("/")
  end

  # The URI Plaid redirects the browser to after OAuth institution login
  # (Chase, Fidelity, ...). It must exactly match an entry under "Allowed
  # redirect URIs" in the Plaid dashboard. `fallback` is the request-derived
  # base URL used when no env configuration exists.
  def self.redirect_uri(fallback:)
    ENV["PLAID_REDIRECT_URI"].presence || "#{app_base_url || fallback}/accounts"
  end

  # Webhook receiver URL Plaid posts to. `fallback` is the request-derived
  # base URL used when no env configuration exists.
  def self.webhook_url(region:, fallback:)
    if region.to_sym == :eu
      ENV["PLAID_EU_WEBHOOK_URL"].presence || "#{app_base_url || fallback}/webhooks/plaid_eu"
    else
      ENV["PLAID_WEBHOOK_URL"].presence || "#{app_base_url || fallback}/webhooks/plaid"
    end
  end

  def initialize(config, region: :us)
    @client = Plaid::PlaidApi.new(
      Plaid::ApiClient.new(config)
    )
    @region = region
  end

  def validate_webhook!(verification_header, raw_body)
    jwks_loader = ->(options) do
      key_id = options[:kid]

      jwk_response = client.webhook_verification_key_get(
        Plaid::WebhookVerificationKeyGetRequest.new(key_id: key_id)
      )

      jwks = JWT::JWK::Set.new([ jwk_response.key.to_hash ])

      jwks.filter! { |key| key[:use] == "sig" }
      jwks
    end

    payload, _header = JWT.decode(
      verification_header, nil, true,
      {
        algorithms: [ "ES256" ],
        jwks: jwks_loader,
        verify_expiration: false
      }
    )

    issued_at = Time.at(payload["iat"])
    raise JWT::VerificationError, "Webhook is too old" if Time.now - issued_at > 5.minutes

    expected_hash = payload["request_body_sha256"]
    actual_hash = Digest::SHA256.hexdigest(raw_body)
    raise JWT::VerificationError, "Invalid webhook body hash" unless ActiveSupport::SecurityUtils.secure_compare(expected_hash, actual_hash)
  end

  def get_link_token(user_id:, webhooks_url:, redirect_url:, accountable_type: nil, access_token: nil, account_selection_enabled: false)
    request_params = {
      user: { client_user_id: user_id },
      client_name: "Sure Finances",
      country_codes: country_codes,
      language: "en",
      webhook: webhooks_url,
      redirect_uri: redirect_url
    }

    if access_token.present?
      request_params[:access_token] = access_token
      request_params[:update] = { account_selection_enabled: true } if account_selection_enabled
    else
      request_params[:transactions] = { days_requested: self.class.max_history_days }
      request_params[:products] = [ get_primary_product(accountable_type) ]
      request_params[:additional_consented_products] = get_additional_consented_products(accountable_type)
    end

    request = Plaid::LinkTokenCreateRequest.new(request_params)

    client.link_token_create(request)
  end

  def exchange_public_token(token)
    request = Plaid::ItemPublicTokenExchangeRequest.new(
      public_token: token
    )

    client.item_public_token_exchange(request)
  end

  def get_item(access_token)
    request = Plaid::ItemGetRequest.new(access_token: access_token)
    client.item_get(request)
  end

  def remove_item(access_token)
    request = Plaid::ItemRemoveRequest.new(access_token: access_token)
    client.item_remove(request)
  end

  def get_item_accounts(access_token)
    request = Plaid::AccountsGetRequest.new(access_token: access_token)
    client.accounts_get(request)
  end

  def get_transactions(access_token, next_cursor: nil)
    cursor = next_cursor
    added = []
    modified = []
    removed = []
    has_more = true

    while has_more
      request = Plaid::TransactionsSyncRequest.new(
        access_token: access_token,
        cursor: cursor,
        options: {
          include_original_description: true
        }
      )

      response = client.transactions_sync(request)

      added += response.added
      modified += response.modified
      removed += response.removed
      has_more = response.has_more
      cursor = response.next_cursor
    end

    TransactionSyncResponse.new(added:, modified:, removed:, cursor:)
  end

  def refresh_transactions(access_token)
    request = Plaid::TransactionsRefreshRequest.new(access_token: access_token)
    client.transactions_refresh(request)
  end

  def get_item_investments(access_token, start_date: nil, end_date: Date.current)
    start_date = start_date || self.class.max_history_days.days.ago.to_date
    holdings, holding_securities = get_item_holdings(access_token: access_token)
    transactions, transaction_securities = get_item_investment_transactions(access_token: access_token, start_date:, end_date:)

    merged_securities = ((holding_securities || []) + (transaction_securities || [])).uniq { |s| s.security_id }

    InvestmentsResponse.new(holdings:, transactions:, securities: merged_securities)
  end

  def get_item_liabilities(access_token)
    request = Plaid::LiabilitiesGetRequest.new({ access_token: access_token })
    response = client.liabilities_get(request)
    response.liabilities
  end

  def get_institution(institution_id)
    request = Plaid::InstitutionsGetByIdRequest.new({
      institution_id: institution_id,
      country_codes: country_codes,
      options: {
        include_optional_metadata: true
      }
    })
    client.institutions_get_by_id(request)
  end

  private
    TransactionSyncResponse = Struct.new :added, :modified, :removed, :cursor, keyword_init: true
    InvestmentsResponse = Struct.new :holdings, :transactions, :securities, keyword_init: true

    def get_item_holdings(access_token:)
      request = Plaid::InvestmentsHoldingsGetRequest.new({ access_token: access_token })
      response = client.investments_holdings_get(request)

      [ response.holdings, response.securities ]
    end

    def get_item_investment_transactions(access_token:, start_date:, end_date:)
      transactions = []
      securities = []
      offset = 0

      loop do
        request = Plaid::InvestmentsTransactionsGetRequest.new(
          access_token: access_token,
          start_date: start_date.to_s,
          end_date: end_date.to_s,
          options: { offset: offset }
        )

        response = client.investments_transactions_get(request)

        transactions += response.investment_transactions
        securities += response.securities

        break if transactions.length >= response.total_investment_transactions
        offset = transactions.length
      end

      [ transactions, securities ]
    end

    # The primary Plaid product to request for a given Sure account type.
    # Investments map to the `investments` product, liability accounts
    # (CreditCard/Loan) to `liabilities`, everything else to `transactions`.
    def get_primary_product(accountable_type)
      return "transactions" if eu?

      case accountable_type
      when "Investment"
        "investments"
      when "CreditCard", "Loan"
        "liabilities"
      else
        "transactions"
      end
    end

    # Additional Plaid products to consent to alongside the primary product.
    #
    # We only request the `liabilities` product when the account being linked is
    # itself a liability (CreditCard/Loan). Plaid's Link filters out any
    # institution that does not support every requested product, so asking for
    # `liabilities` on e.g. an Investment link silently hides investment-only
    # brokerages like E*TRADE that don't offer it.
    def get_additional_consented_products(accountable_type)
      return [] if eu?

      case get_primary_product(accountable_type)
      when "liabilities"
        SUPPORTED_PLAID_PRODUCTS - [ "liabilities" ]
      else
        SUPPORTED_PLAID_PRODUCTS - [ get_primary_product(accountable_type), "liabilities" ]
      end
    end

    def eu?
      region.to_sym == :eu
    end

    def country_codes
      if eu?
        [ "ES", "NL", "FR", "IE", "DE", "IT", "PL", "DK", "NO", "SE", "EE", "LT", "LV", "PT", "BE" ]  # EU supported countries
      else
        [ "US", "CA" ] # US + CA only
      end
    end
end
