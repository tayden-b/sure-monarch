require "test_helper"

class Dedup::MergerTest < ActiveSupport::TestCase
  include EntriesTestHelper

  setup do
    @checking = accounts(:depository)
    @plaid = accounts(:connected)
    @family = families(:dylan_family)
  end

  def make_pair(**overrides)
    imported = create_transaction({
      account: @checking, name: "SQ *CORNER BAKERY",
      date: Date.current - 1.day, amount: 12.50,
      source: "monarch", external_id: "m-1", notes: "from monarch"
    }.merge(overrides[:imported] || {}))
    synced = create_transaction({
      account: @checking, name: "CORNER BAKERY",
      date: Date.current, amount: 12.50,
      source: "plaid", external_id: "p-1"
    }.merge(overrides[:synced] || {}))
    [ imported, synced ]
  end

  test "provider-sourced entry wins over monarch" do
    imported, synced = make_pair

    assert_equal synced, Dedup.preferred_entry(imported, synced)
    assert_equal synced, Dedup.preferred_entry(synced, imported)
  end

  test "monarch beats unprovenanced rows, pending always loses" do
    imported, synced = make_pair
    manual = create_transaction(account: @checking, name: "CORNER BAKERY", date: Date.current, amount: 12.50)
    assert_equal imported, Dedup.preferred_entry(imported, manual)

    synced.transaction.update!(extra: { "plaid" => { "pending" => true } })
    assert_equal imported, Dedup.preferred_entry(imported, synced.reload)
  end

  test "merge keeps winner, destroys loser, records manual_merge" do
    imported, synced = make_pair
    merger = Dedup::Merger.new(winner: synced, loser: imported)

    assert merger.merge!

    synced.reload
    assert_equal "plaid", synced.source
    assert_equal "p-1", synced.external_id
    assert_not Entry.exists?(imported.id)

    merges = synced.transaction.extra["manual_merge"]
    assert_equal 1, merges.size
    assert_equal imported.id.to_s, merges.first["merged_from_entry_id"]
    assert_equal "m-1", merges.first["merged_from_external_id"]
    assert_equal "monarch", merges.first["source"]
    assert_equal "dedup", merges.first["via"]
  end

  test "winner absorbs loser fields it lacks" do
    category = categories(:food_and_drink)
    merchant = merchants(:amazon)
    tag = tags(:one)

    imported, synced = make_pair(
      imported: { category: category, merchant: merchant, tags: [ tag ] },
      synced: {}
    )

    Dedup::Merger.new(winner: synced, loser: imported).merge!
    synced.reload
    tx = synced.transaction

    assert_equal category.id, tx.category_id
    assert_equal merchant.id, tx.merchant_id
    assert_equal imported.notes, synced.notes
    assert_includes tx.tag_ids, tag.id
  end

  test "winner keeps its own category over the loser's" do
    own = categories.first
    other = categories.second
    imported, synced = make_pair(
      imported: { category: other },
      synced: { category: own }
    )

    Dedup::Merger.new(winner: synced, loser: imported).merge!
    assert_equal own.id, synced.transaction.reload.category_id
  end

  test "merging clears needs_review on the winner" do
    imported, synced = make_pair
    synced.transaction.update!(needs_review: true)

    Dedup::Merger.new(winner: synced, loser: imported).merge!
    assert_not synced.transaction.reload.needs_review?
  end

  test "merge marks the winner user-modified" do
    imported, synced = make_pair
    Dedup::Merger.new(winner: synced, loser: imported).merge!
    assert synced.reload.user_modified?
  end

  test "merge is additive across pairs" do
    imported, synced = make_pair
    second_loser = create_transaction(
      account: @checking, name: "CORNER BAKERY #2", date: Date.current, amount: 12.50,
      source: "monarch", external_id: "m-2"
    )

    Dedup::Merger.new(winner: synced, loser: imported).merge!
    Dedup::Merger.new(winner: synced.reload, loser: second_loser).merge!

    merges = synced.reload.transaction.extra["manual_merge"]
    assert_equal 2, merges.size
    assert_equal %w[m-1 m-2], merges.map { |m| m["merged_from_external_id"] }.sort
  end

  test "refuses to merge a pair whose row is already gone" do
    imported, synced = make_pair
    imported.destroy!

    assert Dedup::Merger.new(winner: synced.reload, loser: imported).merge!
    assert Entry.exists?(synced.id)
  end

  test "non-transaction or split entries are not mergeable" do
    imported, synced = make_pair
    valuation = create_valuation(account: @checking)

    assert_not Dedup::Merger.new(winner: synced, loser: valuation).merge!
  end
end
