require "test_helper"

class Dedup::AutoMergerTest < ActiveSupport::TestCase
  include EntriesTestHelper

  setup do
    @family = families(:dylan_family)
    @checking = accounts(:depository)
    @family.update!(auto_merge_duplicates: true)
  end

  test "merges an exact same-account monarch-vs-provider pair" do
    imported = create_transaction(
      account: @checking, name: "SQ *CORNER BAKERY #4412",
      date: Date.current - 1.day, amount: 12.50, currency: "USD",
      source: "monarch", external_id: "m-1"
    )
    synced = create_transaction(
      account: @checking, name: "CORNER BAKERY",
      date: Date.current, amount: 12.50, currency: "USD",
      source: "plaid", external_id: "p-1"
    )

    assert_equal 1, Dedup::AutoMerger.new(family: @family).call

    assert_raises(ActiveRecord::RecordNotFound) { imported.reload }
    assert synced.reload
  end

  test "leaves a wider date gap in the review queue" do
    imported = create_transaction(
      account: @checking, name: "CORNER BAKERY",
      date: Date.current - 3.days, amount: 12.50, currency: "USD",
      source: "monarch", external_id: "m-2"
    )
    synced = create_transaction(
      account: @checking, name: "CORNER BAKERY",
      date: Date.current, amount: 12.50, currency: "USD",
      source: "plaid", external_id: "p-2"
    )

    assert_equal 0, Dedup::AutoMerger.new(family: @family).call
    assert imported.reload
    assert synced.reload
  end

  test "never merges two provider rows" do
    a = create_transaction(
      account: @checking, name: "CORNER BAKERY",
      date: Date.current, amount: 12.50, currency: "USD",
      source: "plaid", external_id: "p-3"
    )
    b = create_transaction(
      account: @checking, name: "CORNER BAKERY",
      date: Date.current, amount: 12.50, currency: "USD",
      source: "simplefin", external_id: "s-1"
    )

    assert_equal 0, Dedup::AutoMerger.new(family: @family).call
    assert a.reload
    assert b.reload
  end

  test "does not merge a cross-account pair" do
    other = accounts(:connected)
    create_transaction(
      account: @checking, name: "CORNER BAKERY",
      date: Date.current, amount: 12.50, currency: "USD",
      source: "monarch", external_id: "m-3"
    )
    create_transaction(
      account: other, name: "CORNER BAKERY",
      date: Date.current, amount: 12.50, currency: "USD",
      source: "plaid", external_id: "p-4"
    )

    assert_equal 0, Dedup::AutoMerger.new(family: @family).call
  end

  test "does nothing when the family setting is off" do
    @family.update!(auto_merge_duplicates: false)

    imported = create_transaction(
      account: @checking, name: "CORNER BAKERY",
      date: Date.current, amount: 12.50, currency: "USD",
      source: "monarch", external_id: "m-4"
    )
    create_transaction(
      account: @checking, name: "CORNER BAKERY",
      date: Date.current, amount: 12.50, currency: "USD",
      source: "plaid", external_id: "p-5"
    )

    assert_equal 0, Dedup::AutoMerger.new(family: @family).call
    assert imported.reload
  end
end
