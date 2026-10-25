require "test_helper"

class Dedup::ScannerTest < ActiveSupport::TestCase
  include EntriesTestHelper

  setup do
    @family = families(:dylan_family)
    @checking = accounts(:depository)
    @plaid = accounts(:connected)
    @scanner = Dedup::Scanner.new(family: @family)
  end

  test "finds same-account duplicate pair from different sources" do
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

    pair = @scanner.candidates.find { |c| c.entry_a == imported || c.entry_b == imported }

    assert pair
    assert_equal synced, pair.winner
    assert_equal imported, pair.loser
    assert pair.same_account?
  end

  test "finds cross-account pair when amounts run the same direction" do
    imported = create_transaction(
      account: @checking, name: "SHELL OIL 5567",
      date: Date.current, amount: 40.00, currency: "USD",
      source: "monarch", external_id: "m-2"
    )
    create_transaction(
      account: @plaid, name: "SHELL OIL",
      date: Date.current, amount: 40.00, currency: "USD",
      source: "plaid", external_id: "p-2"
    )

    assert @scanner.candidates.any? { |c| c.pair_key == Dedup.pair_key(imported, c.loser) || c.loser == imported }
  end

  test "excludes transfer-shaped cross-account pairs (opposite signs)" do
    outflow = create_transaction(
      account: @checking, name: "TRANSFER TO SAVINGS",
      date: Date.current, amount: -500.00, currency: "USD",
      source: "plaid", external_id: "p-3"
    )
    inflow = create_transaction(
      account: @plaid, name: "TRANSFER FROM CHECKING",
      date: Date.current, amount: 500.00, currency: "USD",
      source: "plaid", external_id: "p-4"
    )

    assert_empty @scanner.candidates.select { |c| [ c.entry_a, c.entry_b ].sort_by(&:id) == [ outflow, inflow ].sort_by(&:id) }
  end

  test "respects the date window" do
    create_transaction(account: @checking, name: "TARGET", date: Date.current, amount: 60.00, source: "monarch", external_id: "m-4")
    create_transaction(account: @checking, name: "TARGET", date: Date.current - 10.days, amount: 60.00, source: "plaid", external_id: "p-5")

    assert_equal 0, @scanner.candidates.size
    assert_equal 1, Dedup::Scanner.new(family: @family, date_window: 10).candidates.size
  end

  test "amount must match after sign flip and currency must match" do
    create_transaction(account: @checking, name: "CAFE", date: Date.current, amount: 5.00, source: "monarch", external_id: "m-6")
    create_transaction(account: @checking, name: "CAFE", date: Date.current, amount: 6.00, source: "plaid", external_id: "p-7")
    create_transaction(account: @checking, name: "CAFE", date: Date.current, amount: 5.00, currency: "EUR", source: "plaid", external_id: "p-8")

    assert_equal 0, @scanner.candidates.size
  end

  test "dissimilar names are not candidates" do
    create_transaction(account: @checking, name: "STARBUCKS", date: Date.current, amount: 9.00, source: "monarch", external_id: "m-9")
    create_transaction(account: @checking, name: "WHOLE FOODS", date: Date.current, amount: 9.00, source: "plaid", external_id: "p-9")

    assert_equal 0, @scanner.candidates.size
  end

  test "dismissed pairs are hidden" do
    a = create_transaction(account: @checking, name: "DELTA AIR", date: Date.current, amount: 300.00, source: "monarch", external_id: "m-10")
    b = create_transaction(account: @checking, name: "DELTA AIR", date: Date.current, amount: 300.00, source: "plaid", external_id: "p-10")

    assert_equal 1, @scanner.candidates.size

    Dedup::Dismissal.dismiss!(family: @family, entry_a: a, entry_b: b)

    assert_equal 0, Dedup::Scanner.new(family: @family).candidates.size
    # ...and remains visible when explicitly included.
    assert_equal 1, Dedup::Scanner.new(family: @family, include_dismissed: true).candidates.size
  end

  test "dismissal survives entries recreated with new uuids" do
    a = create_transaction(account: @checking, name: "DELTA AIR", date: Date.current, amount: 300.00, source: "monarch", external_id: "m-11")
    b = create_transaction(account: @checking, name: "DELTA AIR", date: Date.current, amount: 300.00, source: "plaid", external_id: "p-11")
    Dedup::Dismissal.dismiss!(family: @family, entry_a: a, entry_b: b)

    # Re-import destroys and recreates the rows — same external_ids, new uuids.
    a.destroy!
    b.destroy!
    create_transaction(account: @checking, name: "DELTA AIR", date: Date.current, amount: 300.00, source: "monarch", external_id: "m-11")
    create_transaction(account: @checking, name: "DELTA AIR", date: Date.current, amount: 300.00, source: "plaid", external_id: "p-11")

    assert_equal 0, Dedup::Scanner.new(family: @family).candidates.size
  end

  test "same-source pairs score lower than cross-source pairs" do
    same_src_a = create_transaction(account: @checking, name: "LOWES", date: Date.current, amount: 80.00, source: "plaid", external_id: "p-12")
    same_src_b = create_transaction(account: @checking, name: "LOWES", date: Date.current, amount: 80.00, source: "plaid", external_id: "p-13")
    cross_src_a = create_transaction(account: @checking, name: "MACYS", date: Date.current, amount: 90.00, source: "monarch", external_id: "m-12")
    cross_src_b = create_transaction(account: @checking, name: "MACYS", date: Date.current, amount: 90.00, source: "plaid", external_id: "p-14")

    candidates = @scanner.candidates
    same = candidates.find { |c| [ c.entry_a, c.entry_b ].include?(same_src_a) && [ c.entry_a, c.entry_b ].include?(same_src_b) }
    cross = candidates.find { |c| [ c.entry_a, c.entry_b ].include?(cross_src_a) && [ c.entry_a, c.entry_b ].include?(cross_src_b) }

    assert cross.score > same.score
  end

  test "results are capped and ordered by score" do
    3.times do |i|
      create_transaction(account: @checking, name: "CAFE #{i}", date: Date.current, amount: 4.00 + i, source: "monarch", external_id: "m-cap-#{i}")
      create_transaction(account: @checking, name: "CAFE #{i}", date: Date.current, amount: 4.00 + i, source: "plaid", external_id: "p-cap-#{i}")
    end

    limited = Dedup::Scanner.new(family: @family, limit: 2).candidates
    assert_equal 2, limited.size
    assert limited.first.score >= limited.second.score
  end

  test "account scoping restricts the scan" do
    create_transaction(account: @checking, name: "PETCO", date: Date.current, amount: 30.00, source: "monarch", external_id: "m-sc")
    create_transaction(account: @checking, name: "PETCO", date: Date.current, amount: 30.00, source: "plaid", external_id: "p-sc")
    create_transaction(account: @plaid, name: "PETCO", date: Date.current, amount: 30.00, source: "monarch", external_id: "m-sc2")
    create_transaction(account: @plaid, name: "PETCO", date: Date.current, amount: 30.00, source: "plaid", external_id: "p-sc2")

    scoped = Dedup::Scanner.new(family: @family, account: @checking).candidates
    assert_equal 1, scoped.size
    assert scoped.first.same_account?
  end
end
