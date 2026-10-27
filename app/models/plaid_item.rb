class PlaidItem < ApplicationRecord
  include Syncable, Provided, Encryptable, DestroyableLater, ProviderItemOwnable

  # A Plaid access_token only covers the institution the user authenticated
  # to through Link, so a household member may connect their own bank without
  # gaining any visibility into anyone else's connections.
  credential_scope :per_connection

  enum :plaid_region, { us: "us", eu: "eu" }
  enum :status, { good: "good", requires_update: "requires_update" }, default: :good

  # Encrypt sensitive credentials and raw payloads if ActiveRecord encryption is configured
  if encryption_ready?
    encrypts :access_token, deterministic: true
    encrypts :raw_payload
    encrypts :raw_institution_payload
  end

  validates :name, presence: true
  validates :access_token, presence: true, on: :create

  before_destroy :remove_plaid_item

  belongs_to :family
  has_one_attached :logo, dependent: :purge_later

  has_many :plaid_accounts, dependent: :destroy
  has_many :legacy_accounts, through: :plaid_accounts, source: :account

  scope :active, -> { where(scheduled_for_deletion: false) }
  scope :syncable, -> { active }
  scope :ordered, -> { order(created_at: :desc) }
  scope :needs_update, -> { where(status: :requires_update) }

  TRANSACTIONS_REFRESH_COOLDOWN = 5.minutes

  # Raised when an OAuth institution reports missing user consent on a core
  # product during sync. Carries a human-readable message so the failed sync
  # tells the user to reconnect and grant access, instead of storing Plaid's
  # raw HTTP 400 body.
  class ConsentRequiredError < StandardError
    attr_reader :product, :error_code

    def initialize(product:, error_code:, item_name:)
      @product = product
      @error_code = error_code
      super(
        "Plaid says this connection is missing consent for #{product}. " \
        "Reconnect #{item_name} and grant access to #{product} to resume syncing."
      )
    end
  end

  # Key inside raw_payload (otherwise the verbatim /item/get snapshot) holding
  # our own record of products Plaid refused to serve on the latest sync —
  # missing consent, unsupported institution, no matching accounts, or data
  # still being prepared. Each sync's item snapshot replaces raw_payload
  # wholesale, so these entries always reflect the most recent sync: a product
  # that recovers drops off on its own.
  PARTIAL_CONSENT_KEY = "partial_consent"

  # Get accounts from both new and legacy systems
  def accounts
    @accounts ||= plaid_accounts
      .includes(:account, account_provider: :account)
      .map(&:current_account)
      .compact
      .uniq
  end

  def get_update_link_token(webhooks_url:, redirect_url:, account_selection_enabled: false)
    family.get_link_token(
      webhooks_url: webhooks_url,
      redirect_url: redirect_url,
      region: plaid_region,
      access_token: access_token,
      account_selection_enabled: account_selection_enabled
    )
  rescue Plaid::ApiError => e
    error_body = begin
      JSON.parse(e.response_body.to_s)
    rescue JSON::ParserError
      {}
    end

    if error_body["error_code"] == "ITEM_NOT_FOUND"
      # Mark the connection as invalid but don't auto-delete. The caller
      # gets nil so the calling controller can decide what to render.
      update!(status: :requires_update)
      Sentry.capture_exception(e) if defined?(Sentry)
      nil
    else
      # Re-raise so the controller can surface a friendly alert to the user
      # (issue #1792). Swallowing here previously left the Plaid modal frame
      # blank with no actionable signal.
      raise
    end
  end

  # Queue a fresh import after an in-flight sync. Plaid Link can finish adding
  # accounts after the active sync already fetched its account list.
  def sync_later_with_follow_up
    active_sync = syncs.visible.ordered.first
    sync_later

    return unless active_sync&.reload&.in_progress?

    PlaidFollowUpSyncJob.set(wait: PlaidFollowUpSyncJob::RETRY_DELAY).perform_later(self, active_sync_id: active_sync.id)
  end

  def request_transactions_refresh_later
    return unless supports_product?("transactions")
    return unless shared_transactions_refresh_cache?

    refresh_requested = Rails.cache.write(
      transactions_refresh_cache_key,
      true,
      expires_in: TRANSACTIONS_REFRESH_COOLDOWN,
      unless_exist: true
    )

    return unless refresh_requested

    enqueued_job = begin
      PlaidTransactionsRefreshJob.perform_later(self)
    rescue
      Rails.cache.delete(transactions_refresh_cache_key)
      raise
    end

    Rails.cache.delete(transactions_refresh_cache_key) unless enqueued_job
  end

  def sync_later_with_provider_refresh
    request_transactions_refresh_later
    sync_later_with_follow_up
  end

  def import_latest_plaid_data
    PlaidItem::Importer.new(self, plaid_provider: plaid_provider).import
  end

  # Reads the fetched data and updates internal domain objects
  # Generally, this should only be called within a "sync", but can be called
  # manually to "re-sync" the already fetched data
  def process_accounts
    plaid_accounts.each do |plaid_account|
      PlaidAccount::Processor.new(plaid_account).process
    end
  end

  # Once all the data is fetched, we can schedule account syncs to calculate historical balances
  def schedule_account_syncs(parent_sync: nil, window_start_date: nil, window_end_date: nil)
    accounts.each do |account|
      account.sync_later(
        parent_sync: parent_sync,
        window_start_date: window_start_date,
        window_end_date: window_end_date
      )
    end
  end

  # Saves the raw data fetched from Plaid API for this item
  def upsert_plaid_snapshot!(item_snapshot)
    assign_attributes(
      available_products: item_snapshot.available_products,
      billed_products: item_snapshot.billed_products,
      raw_payload: item_snapshot,
    )

    save!
  end

  # Saves the raw data fetched from Plaid API for this item's institution
  def upsert_plaid_institution_snapshot!(institution_snapshot)
    assign_attributes(
      institution_id: institution_snapshot.institution_id,
      institution_url: institution_snapshot.url,
      institution_color: institution_snapshot.primary_color,
      raw_institution_payload: institution_snapshot
    )

    save!
  end

  def supports_product?(product)
    supported_products.include?(product)
  end

  # Records that Plaid refused to serve a product for this item. `retryable`
  # marks codes Plaid resolves without user action (PRODUCT_NOT_READY) — the
  # next sync re-attempts the fetch rather than treating it as declined.
  def record_unavailable_product!(product, error_code:, retryable:)
    payload = raw_payload_hash
    products = payload[PARTIAL_CONSENT_KEY].is_a?(Hash) ? payload[PARTIAL_CONSENT_KEY] : {}

    payload[PARTIAL_CONSENT_KEY] = products.merge(
      product.to_s => {
        "error_code" => error_code,
        "retryable" => retryable,
        "recorded_at" => Time.current.iso8601
      }
    )

    # update_columns, not update!: this runs mid-import inside the accounts
    # transaction, where the association holds not-yet-validated plaid_accounts
    # that would fail the item's own validation.
    update_columns(raw_payload: payload, updated_at: Time.current)
  end

  # Products Plaid refused on the latest sync, keyed by product name with the
  # error details captured at fetch time.
  def unavailable_products
    raw_payload.is_a?(Hash) ? (raw_payload[PARTIAL_CONSENT_KEY] || {}) : {}
  end

  def partial_consent?
    unavailable_products.present?
  end

  # Products that will be re-fetched automatically next sync (e.g.
  # PRODUCT_NOT_READY) vs. those needing the user to reconnect and grant
  # access — the split drives the connection card's notice copy.
  def retryable_unavailable_product_names
    unavailable_products.select { |_product, details| details["retryable"] }.keys
  end

  def declined_unavailable_product_names
    unavailable_products.reject { |_product, details| details["retryable"] }.keys
  end

  private
    # Between `upsert_plaid_snapshot!` and the next `reload`, the raw_payload
    # attribute still holds the Plaid::Item object that was assigned — the
    # JSON round-trip that turns it into a plain Hash hasn't happened yet.
    # `to_hash` reproduces that shape so a partial-consent note merges into
    # the real snapshot instead of replacing it.
    def raw_payload_hash
      payload = raw_payload
      payload = payload.to_hash if payload.respond_to?(:to_hash) && !payload.is_a?(Hash)
      payload.is_a?(Hash) ? payload.deep_dup : {}
    end

    def transactions_refresh_cache_key
      "plaid_item:#{id}:transactions_refresh_requested"
    end

    def shared_transactions_refresh_cache?
      # Compared by name: referencing MemCacheStore autoloads it, which raises
      # LoadError without the dalli gem, and SolidCache isn't a dependency.
      shared_cache = Rails.cache.is_a?(ActiveSupport::Cache::RedisCacheStore) ||
        Rails.cache.class.name.in?(%w[ActiveSupport::Cache::MemCacheStore SolidCache::Store])

      Rails.logger.warn("Plaid transaction refresh requires a shared Rails cache store") unless shared_cache
      shared_cache
    end

    def remove_plaid_item
      return unless plaid_provider.present?

      plaid_provider.remove_item(access_token)
    rescue Plaid::ApiError => e
      json_response = JSON.parse(e.response_body)
      error_code = json_response["error_code"]

      # Continue with deletion if:
      # - ITEM_NOT_FOUND: Item was already deleted by the user on their Plaid portal OR by Plaid support
      # - INVALID_API_KEYS: API credentials are invalid/missing, so we can't communicate with Plaid anyway
      # - Other credential errors: We're deleting our record, so no need to fail if we can't reach Plaid
      ignorable_errors = %w[ITEM_NOT_FOUND INVALID_API_KEYS INVALID_CLIENT_ID INVALID_SECRET]

      unless ignorable_errors.include?(error_code)
        # Log the error but don't prevent deletion - we're removing the item from our database
        # If we can't tell Plaid, we'll at least stop using it on our end
        Rails.logger.warn("Failed to remove Plaid item: #{error_code} - #{json_response['error_message']}")
        Sentry.capture_exception(e) if defined?(Sentry)
      end
    end

    # Plaid splits an item's products across three arrays. If the item has made a
    # request for a product, it is put in the billed_products array. If it is
    # supported but not yet used, it goes in available_products. Products granted
    # through Link's `additional_consented_products` appear in neither -- they are
    # reported in consented_products until the first call actually bills them.
    #
    # That third array matters because it is how we request `transactions` for
    # liability accounts: Provider::Plaid#get_primary_product returns "liabilities"
    # for CreditCard/Loan, so `transactions` can only arrive as an additionally
    # consented product. Omitting it made supports_product?("transactions") false
    # for every Plaid-linked credit card, so PlaidItem::AccountsSnapshot skipped
    # the transactions fetch entirely and those accounts imported balances and
    # liabilities but no transactions at all.
    def supported_products
      consented = raw_payload.is_a?(Hash) ? Array(raw_payload["consented_products"]) : []

      (available_products + billed_products + consented).map(&:to_s).uniq
    end
end
