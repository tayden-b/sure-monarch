require "test_helper"

class ApplyAllRulesJobTest < ActiveJob::TestCase
  include EntriesTestHelper

  setup do
    @family = families(:empty)
    @account = @family.accounts.create!(name: "Test Account", balance: 1000, currency: "USD", accountable: Depository.new)
    @groceries_category = @family.categories.create!(name: "Groceries")
  end

  test "applies all rules for a family" do
    # Create a rule
    rule = Rule.create!(
      family: @family,
      resource_type: "transaction",
      effective_date: 1.day.ago.to_date,
      conditions: [ Rule::Condition.new(condition_type: "transaction_name", operator: "like", value: "Whole Foods") ],
      actions: [ Rule::Action.new(action_type: "set_transaction_category", value: @groceries_category.id) ]
    )

    # Mock RuleJob to verify it gets called for each rule
    RuleJob.expects(:perform_now).with(rule, ignore_attribute_locks: true, execution_type: "manual", claimed_fields: kind_of(Hash)).once

    ApplyAllRulesJob.perform_now(@family)
  end

  test "applies all rules with custom execution type" do
    rule = Rule.create!(
      family: @family,
      resource_type: "transaction",
      effective_date: 1.day.ago.to_date,
      conditions: [ Rule::Condition.new(condition_type: "transaction_name", operator: "like", value: "Test") ],
      actions: [ Rule::Action.new(action_type: "set_transaction_category", value: @groceries_category.id) ]
    )

    RuleJob.expects(:perform_now).with(rule, ignore_attribute_locks: true, execution_type: "scheduled", claimed_fields: kind_of(Hash)).once

    ApplyAllRulesJob.perform_now(@family, execution_type: "scheduled")
  end

  test "applies rules in position order" do
    applied_order = []
    RuleJob.stubs(:perform_now).with { |rule, **_kwargs| applied_order << rule.id; true }

    rules = 3.times.map do |i|
      Rule.create!(
        family: @family,
        resource_type: "transaction",
        position: 3 - i,
        conditions: [ Rule::Condition.new(condition_type: "transaction_name", operator: "like", value: "Test") ],
        actions: [ Rule::Action.new(action_type: "set_transaction_category", value: @groceries_category.id) ]
      )
    end

    ApplyAllRulesJob.perform_now(@family)

    assert_equal rules.sort_by(&:position).map(&:id), applied_order
  end

  test "a failing rule does not stop the rest of the list" do
    good_rule = Rule.create!(
      family: @family,
      resource_type: "transaction",
      position: 2,
      conditions: [ Rule::Condition.new(condition_type: "transaction_name", operator: "like", value: "Test") ],
      actions: [ Rule::Action.new(action_type: "set_transaction_category", value: @groceries_category.id) ]
    )
    bad_rule = Rule.create!(
      family: @family,
      resource_type: "transaction",
      position: 1,
      conditions: [ Rule::Condition.new(condition_type: "transaction_name", operator: "like", value: "Test") ],
      actions: [ Rule::Action.new(action_type: "set_transaction_category", value: @groceries_category.id) ]
    )

    RuleJob.stubs(:perform_now).with(bad_rule, anything).raises(StandardError, "boom")
    RuleJob.expects(:perform_now).with(good_rule, anything).once

    assert_nothing_raised { ApplyAllRulesJob.perform_now(@family) }
  end

  test "active_only skips inactive rules" do
    active_rule = Rule.create!(
      family: @family,
      resource_type: "transaction",
      active: true,
      conditions: [ Rule::Condition.new(condition_type: "transaction_name", operator: "like", value: "Test") ],
      actions: [ Rule::Action.new(action_type: "set_transaction_category", value: @groceries_category.id) ]
    )
    inactive_rule = Rule.create!(
      family: @family,
      resource_type: "transaction",
      active: false,
      conditions: [ Rule::Condition.new(condition_type: "transaction_name", operator: "like", value: "Test") ],
      actions: [ Rule::Action.new(action_type: "set_transaction_category", value: @groceries_category.id) ]
    )

    RuleJob.expects(:perform_now).with(active_rule, anything).once
    RuleJob.expects(:perform_now).with(inactive_rule, anything).never

    ApplyAllRulesJob.perform_now(@family, active_only: true)
  end
end
