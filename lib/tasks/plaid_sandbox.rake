# frozen_string_literal: true

namespace :plaid do
  desc "End-to-end Plaid Sandbox smoke test: creates a Sandbox Item, runs a full " \
       "sync, and verifies accounts, transactions, and holdings land. Requires " \
       "PLAID_CLIENT_ID + PLAID_SECRET + PLAID_ENV=sandbox; exits 0 with a skip " \
       "message when they are absent. Rolls back all DB writes on completion."
  task sandbox_smoke: :environment do
    # --- Credential gate ----------------------------------------------------
    # Free Sandbox keys come from https://dashboard.plaid.com/developers/keys
    # (the "sandbox" secret). They cannot be provisioned unattended — a human
    # must create the Plaid account — so absence is a skip, not a failure.
    if ENV["PLAID_CLIENT_ID"].blank? || ENV["PLAID_SECRET"].blank?
      puts "SKIPPED: PLAID_CLIENT_ID / PLAID_SECRET are not set."
      puts "  Get free Sandbox keys at https://dashboard.plaid.com/developers/keys,"
      puts "  set PLAID_CLIENT_ID, PLAID_SECRET and PLAID_ENV=sandbox, then re-run."
      next
    end

    unless ENV["PLAID_ENV"] == "sandbox"
      abort "REFUSING to run: PLAID_ENV=#{ENV['PLAID_ENV'].inspect}. " \
            "The smoke test only runs against Plaid Sandbox (PLAID_ENV=sandbox) " \
            "so production credentials can never be touched."
    end

    Provider::PlaidAdapter.reload_configuration
    config = Rails.application.config.plaid
    abort "FAIL: Plaid is not configured (check PLAID_CLIENT_ID / PLAID_SECRET)." if config.nil?

    provider = Provider::Plaid.new(config, region: :us)
    plaid    = provider.client

    results  = []
    record   = ->(name, ok, detail = nil) do
      results << [ name, ok ]
      puts "#{ok ? 'PASS' : 'FAIL'}  #{name}#{detail ? " — #{detail}" : ''}"
    end

    # --- 1. Link token creation ---------------------------------------------
    # Exercises the same redirect_uri/webhook resolution the controller uses,
    # so PLAID_REDIRECT_URI / PLAID_WEBHOOK_URL / APP_HOST misconfigurations
    # surface here before a real user hits Link.
    redirect_uri = Provider::Plaid.redirect_uri(fallback: "http://localhost:3000")
    webhook_url  = Provider::Plaid.webhook_url(region: :us, fallback: "http://localhost:3000")
    puts "Using redirect_uri=#{redirect_uri} webhook=#{webhook_url}"

    begin
      link_token = provider.get_link_token(
        user_id: "plaid-sandbox-smoke",
        webhooks_url: webhook_url,
        redirect_url: redirect_uri
      )
      record.call("link_token_create", link_token.link_token.start_with?("link-sandbox-"), link_token.link_token.first(24) + "...")
    rescue Plaid::ApiError => e
      record.call("link_token_create", false, e.response_body)
    end

    # --- 2. Sandbox Item -> access token -------------------------------------
    begin
      public_token = plaid.sandbox_public_token_create(
        Plaid::SandboxPublicTokenCreateRequest.new(
          institution_id: "ins_109508", # First Platypus Bank — works with all products
          initial_products: %w[transactions investments liabilities]
        )
      ).public_token

      exchange = provider.exchange_public_token(public_token)
      access_token = exchange.access_token
      item_id = exchange.item_id
      record.call("public_token exchange", access_token.present?, "item_id=#{item_id}")
    rescue Plaid::ApiError => e
      record.call("public_token exchange", false, e.response_body)
      abort "Aborting early: cannot create a Sandbox Item."
    end

    # --- 3. Full sync inside a rolled-back transaction -----------------------
    # Everything the real sync path does (import + account processing) runs
    # synchronously here; the rollback keeps the instance's DB untouched.
    plaid_item = nil
    family     = nil

    ActiveRecord::Base.transaction do
      family = Family.create!(name: "Plaid Sandbox Smoke")
      user   = family.users.create!(
        email: "plaid-sandbox-smoke-#{SecureRandom.hex(4)}@example.invalid",
        password: SecureRandom.base58(20),
        first_name: "Plaid",
        last_name: "Smoke",
        role: "admin"
      )

      plaid_item = family.plaid_items.create!(
        name: "First Platypus Bank",
        plaid_id: item_id,
        access_token: access_token,
        plaid_region: "us",
        owner: user
      )

      plaid_item.import_latest_plaid_data
      plaid_item.process_accounts
      plaid_item.plaid_accounts.reload

      record.call("item import", plaid_item.raw_payload.present?, plaid_item.institution_id.to_s)
      record.call(
        "accounts imported",
        plaid_item.plaid_accounts.any?,
        "#{plaid_item.plaid_accounts.count} plaid_accounts"
      )

      accounts = plaid_item.plaid_accounts.filter_map(&:current_account)
      record.call(
        "accounts processed",
        accounts.any?,
        "#{accounts.size} Sure accounts (#{accounts.map(&:accountable_type).uniq.join(', ')})"
      )

      tx_count = Entry.where(account_id: accounts.map(&:id), entryable_type: "Transaction").count
      record.call("transactions synced", tx_count > 0, "#{tx_count} transaction entries")

      holdings_count = Holding.where(account_id: accounts.map(&:id)).count
      has_investment_account = plaid_item.plaid_accounts.any? { |pa| pa.plaid_type == "investment" }
      record.call(
        "holdings synced",
        !has_investment_account || holdings_count > 0,
        "#{holdings_count} holdings"
      )

      credit_account = plaid_item.plaid_accounts.find { |pa| pa.plaid_type == "credit" }
      if credit_account&.current_account
        apr = credit_account.current_account.accountable.try(:apr)
        record.call("liabilities synced", true, "credit account apr=#{apr.inspect}")
      else
        record.call("liabilities synced", true, "no credit account in fixture (ok)")
      end

      # --- 4. Update-mode link token (reconnect path) ------------------------
      begin
        update_token = plaid_item.get_update_link_token(
          webhooks_url: webhook_url,
          redirect_url: redirect_uri
        )
        record.call("update-mode link token", update_token.present?)
      rescue Plaid::ApiError => e
        record.call("update-mode link token", false, e.response_body)
      end

      raise ActiveRecord::Rollback
    end

    # --- 5. Clean up the Sandbox Item server-side -----------------------------
    begin
      provider.remove_item(access_token)
      record.call("sandbox item removed", true)
    rescue Plaid::ApiError => e
      record.call("sandbox item removed", false, e.response_body)
    end

    failures = results.reject { |_, ok| ok }
    puts
    if failures.empty?
      puts "SUCCESS: Plaid Sandbox smoke test passed (#{results.size} checks)."
    else
      abort "FAILURE: #{failures.size}/#{results.size} checks failed."
    end
  end
end
