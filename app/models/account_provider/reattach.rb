# Moves a provider link from a provider-created "shell" account onto an
# existing (usually imported) account, then retires the shell.
#
# First sync creates an Account per provider account when auto-attach can't
# identify an imported twin. "Attach to existing" later moves that link: the
# AccountProvider row, the provider's own entries, holdings and balance
# anchors are re-pointed at the target account, the emptied shell is queued
# for destruction, and the target syncs.
#
# A source account only qualifies when it carries nothing but provider-fed
# data — see .reattachable? — so user-entered data is never swept sideways.
class AccountProvider::Reattach
  Error = Class.new(StandardError)

  attr_reader :account_provider, :target_account

  def initialize(account_provider:, target_account:)
    @account_provider = account_provider
    @target_account = target_account
  end

  # A provider-created shell: the sync built it (it carries no Monarch
  # mapping) and every ledger line on it came from this provider's feed.
  # Transactions with any other provenance — another feed's source, or a
  # hand-entered row with no source at all — mean the user adopted the
  # account, so it is real data, not a disposable shell. Valuations are
  # exempt: the sync writes them source-less, and reconciliations are
  # balance anchors a move should carry over anyway.
  def self.reattachable?(account_provider)
    account = account_provider.account
    return false if account.nil?

    return false if MonarchSourceMapping.exists?(
      family_id: account.family_id,
      collection: "accounts",
      record_type: "Account",
      record_id: account.id
    )

    !account.entries
      .where(entryable_type: "Transaction")
      .where("COALESCE(entries.source, '') <> ?", provider_source(account_provider))
      .exists?
  end

  # Source written onto the entries this provider's processor creates —
  # "PlaidAccount" -> "plaid", "CoinbaseAccount" -> "coinbase", etc.
  def self.provider_source(account_provider)
    account_provider.provider_type.demodulize.underscore.delete_suffix("_account")
  end

  # The accountable class the feed implies — nil when we can't infer one, so
  # unknown provider kinds skip the class check. A wrong-class attach would
  # misclassify the target permanently (a credit feed on a depository flips
  # liability-vs-asset, hence the balance sign) and can't be undone: after
  # the move the source carries non-provider data and is never reattachable.
  def self.expected_accountable_class(provider)
    case provider
    when PlaidAccount
      PlaidAccount::TypeMappable.accountable_class(provider.plaid_type)
    when CoinbaseAccount, KrakenAccount
      Crypto
    end
  rescue PlaidAccount::TypeMappable::UnknownAccountTypeError
    nil
  end

  def reattachable?
    self.class.reattachable?(account_provider)
  end

  def call
    validate!

    AccountProvider.transaction do
      account_provider.update!(account: target_account)
      move_records!
      source_account.mark_for_deletion!
    end

    DestroyJob.perform_later(source_account)
    target_account.sync_later

    account_provider
  end

  private
    def source_account
      @source_account ||= account_provider.account
    end

    def validate!
      raise Error, "Provider account is not linked" if source_account.nil?
      raise Error, "Accounts must belong to the same family" if source_account.family_id != target_account.family_id
      raise Error, "Cannot reattach to the same account" if source_account.id == target_account.id

      unless reattachable?
        raise Error, "Linked account has non-provider data and cannot be detached automatically"
      end

      if target_account.account_providers.exists?(provider_type: account_provider.provider_type)
        raise Error, "Target account already has a #{account_provider.provider_type} provider link"
      end

      expected_class = self.class.expected_accountable_class(account_provider.provider)
      if expected_class && target_account.accountable.class != expected_class
        raise Error, "Cannot attach a #{account_provider.provider_type} feed to a #{target_account.accountable.class} account"
      end
    end

    # Everything on the shell follows the feed to the target — the provider's
    # transactions and the sync-written balance anchors alike. Holdings keep
    # their account_provider_id; only the owning account changes.
    def move_records!
      source_account.entries.update_all(account_id: target_account.id, updated_at: Time.current)
      source_account.holdings.update_all(account_id: target_account.id, updated_at: Time.current)
    end
end
