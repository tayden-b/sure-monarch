namespace :providers do
  # Attach a provider account to an existing account by id — for cases the
  # auto-attach rules can't see (e.g. an imported account whose name carries
  # no mask). When the provider account is already linked to a
  # provider-created shell, the link is moved and the emptied shell is
  # destroyed instead.
  #
  #   bin/rails "providers:attach[<plaid_account_id>,<account_id>]"
  desc "Attach a provider account to an existing account: providers:attach[<plaid_account_id>,<account_id>]"
  task :attach, [ :plaid_account_id, :account_id ] => :environment do |_t, args|
    plaid_account = PlaidAccount.find(args.fetch(:plaid_account_id))
    account = Account.find(args.fetch(:account_id))

    if plaid_account.plaid_item.family_id != account.family_id
      abort "Plaid account and target account belong to different families — refusing."
    end

    if plaid_account.account_provider.present?
      reattach = AccountProvider::Reattach.new(
        account_provider: plaid_account.account_provider,
        target_account: account
      )

      unless reattach.reattachable?
        abort "Plaid account #{plaid_account.id} is linked to an account carrying non-provider data — refusing to move it."
      end

      reattach.call
      puts "Moved PlaidAccount #{plaid_account.id} onto Account #{account.id} (#{account.name}); previous account queued for deletion."
    elsif plaid_account.account.present?
      abort "Plaid account #{plaid_account.id} is already linked to Account #{plaid_account.account_id} (legacy link)."
    else
      if account.account_providers.exists?(provider_type: "PlaidAccount")
        abort "Account #{account.id} already has a Plaid provider link."
      end

      AccountProvider.create!(account: account, provider: plaid_account, provider_type: "PlaidAccount")
      account.sync_later
      puts "Linked PlaidAccount #{plaid_account.id} to Account #{account.id} (#{account.name}) and queued a sync."
    end
  end
end
