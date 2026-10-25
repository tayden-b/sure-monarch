require "test_helper"

class Dedup::CandidatesControllerTest < ActionDispatch::IntegrationTest
  include EntriesTestHelper

  setup do
    sign_in users(:family_admin)
    @family = families(:dylan_family)
    @checking = accounts(:depository)
  end

  def make_pair
    imported = create_transaction(
      account: @checking, name: "SQ *CORNER BAKERY",
      date: Date.current - 1.day, amount: 12.50,
      source: "monarch", external_id: "m-1"
    )
    synced = create_transaction(
      account: @checking, name: "CORNER BAKERY",
      date: Date.current, amount: 12.50,
      source: "plaid", external_id: "p-1"
    )
    [ imported, synced ]
  end

  test "index renders grouped candidate pairs" do
    imported, synced = make_pair

    get dedup_candidates_url

    assert_response :success
    assert_includes response.body, imported.name
    assert_includes response.body, synced.name
  end

  test "index filters by confidence" do
    make_pair

    get dedup_candidates_url(confidence: "high")
    assert_response :success

    get dedup_candidates_url(confidence: "nonsense")
    assert_response :success
  end

  test "merge keeps the provider row and removes the imported one" do
    imported, synced = make_pair

    post merge_dedup_candidates_url, params: { entry_a_id: imported.id, entry_b_id: synced.id }

    assert_redirected_to dedup_candidates_url
    assert Entry.exists?(synced.id)
    assert_not Entry.exists?(imported.id)
    assert_equal "m-1", synced.reload.transaction.extra.dig("manual_merge", 0, "merged_from_external_id")
  end

  test "dismiss persists a dismissal so the pair stops surfacing" do
    imported, synced = make_pair

    assert_difference "Dedup::Dismissal.count", 1 do
      post dismiss_dedup_candidates_url, params: { entry_a_id: imported.id, entry_b_id: synced.id }
    end

    assert_redirected_to dedup_candidates_url

    get dedup_candidates_url
    assert_not_includes response.body, imported.name
  end

  test "merge with a missing entry redirects with an alert" do
    imported, _synced = make_pair

    post merge_dedup_candidates_url, params: { entry_a_id: imported.id, entry_b_id: Entry.new.id }

    assert_redirected_to dedup_candidates_url
    assert_equal I18n.t("dedup.candidates.shared.invalid_pair"), flash[:alert]
  end

  test "entries from another family are rejected" do
    imported, _synced = make_pair
    foreign_account = families(:empty).accounts.create!(
      name: "Foreign Checking", balance: 0, currency: "USD", accountable: Depository.new
    )
    foreign = create_transaction(
      account: foreign_account, name: "CORNER BAKERY",
      date: Date.current, amount: 12.50, source: "plaid", external_id: "f-1"
    )

    post merge_dedup_candidates_url, params: { entry_a_id: imported.id, entry_b_id: foreign.id }

    assert_redirected_to dedup_candidates_url
    assert_equal I18n.t("dedup.candidates.shared.invalid_pair"), flash[:alert]
    assert Entry.exists?(imported.id)
    assert Entry.exists?(foreign.id)
  end
end
