class PlaidItemsController < ApplicationController
  include StreamExtensions, ConnectorAuthorizable

  connects_provider PlaidItem

  before_action :set_plaid_item, only: %i[edit destroy sync]
  before_action :require_connector_create!, only: %i[new create select_existing_account link_existing_account]
  before_action :require_connector_manage!, only: %i[edit destroy sync]

  def new
    region = params[:region] == "eu" ? :eu : :us

    @link_token = Current.family.get_link_token(
      webhooks_url: plaid_webhooks_url(region),
      redirect_url: plaid_redirect_url,
      accountable_type: params[:accountable_type] || "Depository",
      region: region
    )
  rescue Plaid::ApiError => e
    handle_link_token_error(e)
  end

  def edit
    @link_token = @plaid_item.get_update_link_token(
      webhooks_url: plaid_webhooks_url(@plaid_item.plaid_region),
      redirect_url: plaid_redirect_url,
      account_selection_enabled: @plaid_item.us? && params[:add_accounts] == "true",
    )
  rescue Plaid::ApiError => e
    handle_link_token_error(e)
  end

  def create
    Current.family.create_plaid_item!(
      public_token: plaid_item_params[:public_token],
      item_name: item_name,
      region: plaid_item_params[:region]
    )

    redirect_to accounts_path, notice: t(".success")
  end

  def destroy
    @plaid_item.destroy_later
    redirect_to accounts_path, notice: t(".success")
  end

  def sync
    @plaid_item.sync_later_with_provider_refresh

    respond_to do |format|
      format.html { redirect_back_or_to accounts_path }
      format.json { head :ok }
    end
  end

  def select_existing_account
    @account = Current.family.accounts.find(params[:account_id])
    @region = params[:region] || "us"

    # A non-admin reaches this action now, so the target account needs its own
    # check -- family membership alone is not authorisation to attach a feed to
    # someone else's account.
    return if !Current.user.admin? && !require_account_permission!(@account)

    # Get all Plaid accounts from this family's Plaid items for the specified region
    # that are not yet linked to any account — plus provider-created shells
    # (first sync built them before this account existed), whose link can be
    # moved onto the chosen account instead. A member only sees the items
    # they own; an admin sees the family's.
    scope = Current.family.plaid_items.where(plaid_region: @region)
    scope = scope.owned_by(Current.user) unless Current.user.admin?

    @available_plaid_accounts = scope
      .includes(plaid_accounts: :account_provider)
      .flat_map(&:plaid_accounts)
      .select { |pa| selectable_for_account?(pa) }

    if @available_plaid_accounts.empty?
      redirect_to account_path(@account), alert: t(".no_available_accounts")
    end
  end

  def link_existing_account
    @account = Current.family.accounts.find(params[:account_id])
    plaid_account = PlaidAccount.find(params[:plaid_account_id])

    # Verify the Plaid account belongs to this family's Plaid items, and that
    # this user may act on that connection at all -- a member must not be able
    # to attach a connection someone else owns.
    unless Current.family.plaid_items.include?(plaid_account.plaid_item) &&
           plaid_account.plaid_item.manageable_by?(Current.user)
      redirect_to account_path(@account), alert: t(".invalid_account")
      return
    end

    return if !Current.user.admin? && !require_account_permission!(@account)

    # Already linked to a provider-created shell → move the feed onto the
    # chosen account and retire the shell. Linked to anything else stays an
    # error — a link is never silently moved off real data.
    if plaid_account.account_provider.present?
      reattach = AccountProvider::Reattach.new(
        account_provider: plaid_account.account_provider,
        target_account: @account
      )

      unless reattach.reattachable?
        redirect_to account_path(@account), alert: t(".already_linked")
        return
      end

      begin
        reattach.call
        redirect_to accounts_path, notice: t(".reattach_success")
      rescue AccountProvider::Reattach::Error => e
        redirect_to account_path(@account), alert: e.message
      end
      return
    elsif plaid_account.account.present?
      redirect_to account_path(@account), alert: t(".already_linked")
      return
    end

    # Create the link via AccountProvider
    AccountProvider.create!(
      account: @account,
      provider: plaid_account
    )

    redirect_to accounts_path, notice: t(".success")
  end

  private

    # Unlinked Plaid accounts are the normal choices. One linked to a
    # provider-created shell is also offered — choosing it re-attaches the
    # feed here and destroys the empty shell (AccountProvider::Reattach).
    def selectable_for_account?(plaid_account)
      if plaid_account.account_provider.nil? && plaid_account.account.nil?
        true
      else
        plaid_account.account_provider.present? &&
          AccountProvider::Reattach.reattachable?(plaid_account.account_provider)
      end
    end

    def set_plaid_item
      @plaid_item = Current.family.plaid_items.find(params[:id])
    end

    def plaid_item_params
      params.require(:plaid_item).permit(:public_token, :region, metadata: {})
    end

    def item_name
      plaid_item_params.dig(:metadata, :institution, :name)
    end

    # When `link_token/create` (or the update equivalent) raises, surface a
    # friendly alert to the user instead of letting the modal frame render
    # blank. Plaid configuration/product-access errors are the common case for
    # self-hosted users — without this, the Link modal simply never opens and
    # the only signal lives in server logs.
    def handle_link_token_error(error)
      error_body = safe_parse_plaid_error(error)
      error_code = error_body["error_code"].to_s

      Rails.logger.warn(
        "Plaid link_token request failed: #{error_code} - #{error_body['error_message']}"
      )
      Sentry.capture_exception(error) if defined?(Sentry)

      alert = friendly_link_token_alert(error_code, error_body["error_message"])

      respond_to do |format|
        format.html { redirect_to accounts_path, alert: alert }
        format.turbo_stream { stream_redirect_to(accounts_path, alert: alert) }
      end
    end

    def safe_parse_plaid_error(error)
      JSON.parse(error.response_body.to_s)
    rescue JSON::ParserError
      {}
    end

    # Plaid surfaces its own actionable copy on configuration / product-access
    # failures (e.g. "Your account is not enabled for the following products
    # [...]. To request access, visit dashboard.plaid.com..."). Those messages
    # are safe to show verbatim — they describe a Plaid-side config issue,
    # not user data. For everything else we fall back to a generic message
    # and rely on the log + Sentry trail.
    SHOWABLE_PLAID_ERROR_CODES = %w[
      INVALID_PRODUCT
      PRODUCTS_NOT_SUPPORTED
      NO_PRODUCTS_PERMISSION
      ADDITION_LIMIT
      INVALID_INSTITUTION
      INSTITUTION_NOT_ENABLED_IN_REGION
      INSTITUTION_NOT_SUPPORTED
    ].freeze

    def friendly_link_token_alert(error_code, error_message)
      if SHOWABLE_PLAID_ERROR_CODES.include?(error_code) && error_message.present?
        t("plaid_items.errors.link_token_with_message", message: error_message)
      else
        t("plaid_items.errors.link_token_generic")
      end
    end

    def plaid_redirect_url
      Provider::Plaid.redirect_uri(fallback: request.base_url)
    end

    def plaid_webhooks_url(region)
      Provider::Plaid.webhook_url(region: region, fallback: default_webhooks_base_url)
    end

    # Request-derived base for webhooks when no env override exists. In
    # production the host Plaid sees is whatever public address served this
    # request; in development it's the DEV_WEBHOOKS_URL tunnel (e.g. ngrok)
    # or root_url.
    def default_webhooks_base_url
      return request.base_url if Rails.env.production?

      ENV.fetch("DEV_WEBHOOKS_URL", root_url.chomp("/"))
    end
end
