# "Invested" for a period: cash that moved into investment accounts minus
# cash that came back out — the savings side of the cash-flow statement.
#
# Contributions are kind investment_contribution rows: transfer outflow legs
# into investment/crypto accounts, plus provider-booked Contribution/Buy
# activity inside those accounts (the same population upstream counts as an
# expense — see ScopedTransactionsQuery#classification_sql).
#
# Withdrawals are cash leaving the investing envelope: 'Withdrawal'-labeled
# rows in investment accounts, plus outflow legs of Transfers whose
# destination is not an investment/crypto account. Those legs carry kind
# funds_movement (the kind is assigned from the destination account), so the
# destination's account type is checked through the Transfer pair rather than
# by kind.
#
# Same scoping as the other income-statement queries (family, account flag,
# tax-advantaged exclusion, finance-account filter), so the Invested figure
# always lives in the same population as Income/Expenses and the Sankey
# branches sum to Cash Flow.
class IncomeStatement::InvestedFlows
  include IncomeStatement::ScopedTransactionsQuery

  Result = Data.define(:contributions, :withdrawals, :net, :currency)

  def initialize(family, transactions_scope:, date_range:, included_account_ids: nil, account_flag: nil)
    @family = family
    @transactions_scope = transactions_scope
    @date_range = date_range
    @included_account_ids = included_account_ids
    @account_flag = account_flag

    validate_date_range!
  end

  def call
    # No finance accounts means no transactions to report
    return zero_result if @included_account_ids&.empty?

    row = ActiveRecord::Base.connection.select_all(query_sql).first || {}

    Result.new(
      contributions: row["contributions"].to_d,
      withdrawals: row["withdrawals"].to_d,
      net: row["contributions"].to_d - row["withdrawals"].to_d,
      currency: @family.currency
    )
  end

  private
    def zero_result
      Result.new(contributions: 0, withdrawals: 0, net: 0, currency: @family.currency)
    end

    def query_sql
      ActiveRecord::Base.sanitize_sql_array([
        <<~SQL,
          SELECT
            COALESCE(SUM(
              CASE WHEN t.kind = 'investment_contribution' THEN #{abs_amount_sql} ELSE 0 END
            ), 0) AS contributions,
            COALESCE(SUM(
              CASE WHEN t.kind = 'investment_contribution' THEN 0 WHEN #{withdrawal_condition_sql} THEN #{abs_amount_sql} ELSE 0 END
            ), 0) AS withdrawals
          FROM (#{@transactions_scope.to_sql}) t
          #{entries_join_sql("t")}
          #{accounts_join_sql}
          #{exchange_rates_join_sql}
          WHERE a.family_id = :family_id
            AND a.status IN ('draft', 'active')
            AND ae.excluded = false
            AND a.#{account_flag_column} = false
            #{exclude_tax_advantaged_sql}
            #{include_finance_accounts_sql}
            AND (t.kind = 'investment_contribution' OR #{withdrawal_condition_sql});
        SQL
        sql_params
      ])
    end

    # Entry amount in family currency, magnitude only — contribution outflows
    # and provider rows disagree on sign, and Invested is a flow measure.
    def abs_amount_sql
      "ABS(ae.amount * COALESCE(er.rate, 1))"
    end

    # Cash leaving the investing envelope: a row in an investment/crypto
    # account that is either labeled a Withdrawal or is the outflow leg of a
    # Transfer whose destination is outside investment/crypto.
    def withdrawal_condition_sql
      <<~SQL.squish
        a.accountable_type IN ('Investment', 'Crypto')
        AND (
          t.investment_activity_label = 'Withdrawal'
          OR EXISTS (
            SELECT 1
            FROM transfers wt
            JOIN transactions wt_in ON wt_in.id = wt.inflow_transaction_id
            JOIN entries we ON we.entryable_id = wt_in.id AND we.entryable_type = 'Transaction'
            JOIN accounts wa ON wa.id = we.account_id
            WHERE wt.outflow_transaction_id = t.id
              AND wa.accountable_type NOT IN ('Investment', 'Crypto')
          )
        )
      SQL
    end

    def sql_params
      params = base_sql_params
      params[:included_account_ids] = @included_account_ids if @included_account_ids
      params
    end
end
