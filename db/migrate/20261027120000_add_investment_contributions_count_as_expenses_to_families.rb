class AddInvestmentContributionsCountAsExpensesToFamilies < ActiveRecord::Migration[8.1]
  def change
    # Monarch parity default: upstream counts investment contributions as
    # expenses; this fork treats them as savings unless a family opts back in.
    add_column :families, :investment_contributions_count_as_expenses, :boolean, default: false, null: false
  end
end
