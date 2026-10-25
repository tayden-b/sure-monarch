# Spend grouped by merchant for a period, powering the reports "by merchant"
# breakdown and its CSV export. Shares the IncomeStatement scoping via
# ScopedTransactionsQuery (posted transactions in report-included,
# non-tax-advantaged accounts, excluding budget-excluded kinds and excluded
# entries, converted at each entry's day exchange rate) so the figures agree
# with every other income statement number.
#
# Direction mirrors the reports "Activity Breakdown" table, which counts an
# entry as spend when `entries.amount > 0` — uncategorized and
# expense-classified rows alike. That keeps this table's rows
# cross-checkable against the sibling category table on the same page.
class IncomeStatement::MerchantTotals
  include IncomeStatement::ScopedTransactionsQuery

  def initialize(family, transactions_scope:, date_range:, included_account_ids: nil, account_flag: nil, limit: nil)
    @family = family
    @transactions_scope = transactions_scope
    @date_range = date_range
    @included_account_ids = included_account_ids
    @account_flag = account_flag
    @limit = limit

    validate_date_range!
  end

  def call
    # No finance accounts means no transactions to report
    return [] if @included_account_ids&.empty?

    ActiveRecord::Base.connection.select_all(query_sql).map do |row|
      MerchantTotal.new(
        merchant_name: row["merchant_name"],
        color: row["color"],
        logo_url: row["logo_url"],
        total: row["total"],
        transactions_count: row["transactions_count"]
      )
    end
  end

  private
    MerchantTotal = Data.define(:merchant_name, :color, :logo_url, :total, :transactions_count)

    def query_sql
      ActiveRecord::Base.sanitize_sql_array([ query_sql_body, sql_params ])
    end

    # Grouped by merchant NAME rather than id: the transactions feed filters
    # merchants by name, so same-named merchant records (a FamilyMerchant and
    # a ProviderMerchant duplicate) must collapse into one row for the
    # drill-down link to reproduce the total. NULL merchant_id lands in a
    # single "No merchant" bucket that ranks by spend like any named merchant.
    def query_sql_body
      <<~SQL
        SELECT
          m.name as merchant_name,
          MAX(m.color) as color,
          MAX(m.logo_url) as logo_url,
          SUM(#{converted_amount_sql("at")}) as total,
          COUNT(ae.id) as transactions_count
        FROM (#{@transactions_scope.to_sql}) at
        #{entries_join_sql("at")}
        #{accounts_join_sql}
        LEFT JOIN merchants m ON m.id = at.merchant_id
        #{exchange_rates_join_sql}
        WHERE at.kind NOT IN (#{budget_excluded_kinds_sql})
          #{investment_activity_label_sql("at")}
          AND ae.excluded = false
          AND ae.amount > 0
          AND a.family_id = :family_id
          AND a.status IN ('draft', 'active')
          AND a.#{account_flag_column} = false
          #{exclude_tax_advantaged_sql}
          #{include_finance_accounts_sql}
        GROUP BY m.name
        ORDER BY total DESC, merchant_name ASC NULLS LAST
        #{limit_sql}
      SQL
    end

    def limit_sql
      @limit ? "LIMIT #{@limit.to_i}" : ""
    end

    def sql_params
      params = base_sql_params(start_date: @date_range.begin, end_date: @date_range.end)

      params[:included_account_ids] = @included_account_ids if @included_account_ids

      params
    end
end
