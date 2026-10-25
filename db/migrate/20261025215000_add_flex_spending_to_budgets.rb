# Monarch's "flex" number: a discretionary pool for spend no category
# envelope claims. Stored on the budget itself — same shape as
# `budgeted_spending`/`expected_income` — so it copies month to month.
class AddFlexSpendingToBudgets < ActiveRecord::Migration[8.1]
  def change
    add_column :budgets, :flex_spending, :decimal, precision: 19, scale: 4
  end
end
