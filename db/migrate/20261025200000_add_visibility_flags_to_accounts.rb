# frozen_string_literal: true

# Monarch keeps four independent per-account visibility flags. Sure only had
# `status` + `exclude_from_reports`, so the importer could not preserve
# "hidden from lists but still counted" or "hidden from budget" accounts.
#
#   hide_from_list       - out of account lists/sidebars, still counted everywhere
#   include_in_net_worth - when false, balance is out of net worth only
#   hide_in_budget       - transactions out of budget actuals only
#
# `exclude_from_reports` keeps its column but is re-scoped to transaction
# report surfaces only (income statements / reports); net worth and budget
# exclusion moved to the two dedicated flags above.
class AddVisibilityFlagsToAccounts < ActiveRecord::Migration[8.1]
  def change
    add_column :accounts, :hide_from_list, :boolean, null: false, default: false
    add_column :accounts, :include_in_net_worth, :boolean, null: false, default: true
    add_column :accounts, :hide_in_budget, :boolean, null: false, default: false
  end
end
