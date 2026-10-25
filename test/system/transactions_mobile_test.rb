require "application_system_test_case"

# The phone is the primary surface for transactions: Monarch's ledger, filter
# and categorize flows are all one-thumb flows, so "fits a phone" is a
# correctness property rather than a polish one.
#
# These assertions guard three mobile-only breakpoints the desktop suite
# never exercises: the 50vh filter popover becoming a full-height sheet, the
# bottom-anchored bulk-selection bar, and the categorize wizard's two-column
# grid collapsing to one column without horizontal overflow.
class TransactionsMobileTest < ApplicationSystemTestCase
  PHONE = [ 375, 812 ].freeze

  setup do
    sign_in @user = users(:family_admin)
    @family = @user.family

    Entry.delete_all # clean slate
    3.times do |i|
      create_transaction("mobile txn #{i}", (i + 1).days.ago.to_date, 100 + i)
    end
    @transaction = @family.entries.transactions.reverse_chronological.first

    page.driver.browser.manage.window.resize_to(*PHONE)
  end

  teardown do
    page.driver.browser.manage.window.resize_to(1400, 1400)
  end

  test "transactions list does not scroll sideways on a phone" do
    visit transactions_url
    assert_text @transaction.name
    assert_no_horizontal_scroll("the transactions list")
  end

  test "bottom nav links to accounts on a phone" do
    visit transactions_url
    within("nav[data-viewport-target='bottomNav']") do
      assert_link I18n.t("layouts.application.nav.accounts"), href: accounts_path
    end
  end

  test "filter sheet is a full-height sheet with reachable actions on a phone" do
    visit transactions_url
    find("#transaction-filters-button").click
    assert_selector "#transaction-filters-menu", visible: true

    sheet = page.evaluate_script(<<~JS)
      (() => {
        const r = document.querySelector("#transaction-filters-menu").getBoundingClientRect();
        return { top: r.top, bottom: r.bottom, height: r.height, innerH: window.innerHeight };
      })()
    JS

    # A sheet that starts above the viewport clips its own tab strip (this
    # happened when the popover relied on flip() alone); a short one wastes
    # the screen. Both are failures of "full-height".
    assert_operator sheet["top"], :>=, 0, "the filter sheet renders above the viewport"
    assert_operator sheet["height"], :>=, sheet["innerH"] * 0.6, "the filter sheet is not full-height"
    assert_operator sheet["bottom"], :<=, sheet["innerH"], "the filter sheet extends below the viewport"

    within "#transaction-filters-menu" do
      assert_button I18n.t("transactions.searches.menu.apply"), visible: true
      assert_button I18n.t("transactions.searches.menu.cancel"), visible: true
    end

    assert_no_horizontal_scroll("the transactions list with the filter sheet open")
  end

  test "bulk selection bar stays in view on a phone" do
    visit transactions_url
    find("#toggle-checkboxes-button").click

    transaction_checkbox(@transaction).click

    within "#entry-selection-bar" do
      assert_text "1 transaction selected"
    end

    bar = page.evaluate_script(<<~JS)
      (() => {
        const r = document.querySelector("#entry-selection-bar").getBoundingClientRect();
        return { top: r.top, bottom: r.bottom, innerH: window.innerHeight };
      })()
    JS

    # Bottom-anchored means inside the viewport, not off the bottom edge.
    assert_operator bar["bottom"], :<=, bar["innerH"], "the selection bar is pushed below the viewport"
    assert_operator bar["top"], :>=, 0, "the selection bar renders above the viewport"

    assert_no_horizontal_scroll("the transactions list with the selection bar open")
  end

  test "transaction drawer is usable on a phone" do
    visit transactions_url
    find("a[data-clickable-row-target='link']", match: :first).click

    within("dialog") do
      assert_selector "button[aria-label='#{I18n.t("ds.dialog.close")}']", visible: true
    end
    assert_no_horizontal_scroll("the transaction drawer")
  end

  test "categorize wizard does not scroll sideways on a phone" do
    visit transactions_categorize_url
    assert_text @transaction.name
    assert_no_horizontal_scroll("the categorize wizard")
  end

  private
    # The document must never be wider than the viewport, and neither must the
    # scroll container inside it.
    def assert_no_horizontal_scroll(label)
      overflow = page.evaluate_script(<<~JS)
        (() => {
          const main = document.querySelector("#main");
          return {
            doc: document.documentElement.scrollWidth - document.documentElement.clientWidth,
            main: main ? main.scrollWidth - main.clientWidth : 0
          };
        })()
      JS

      assert_operator overflow["doc"], :<=, 1, "#{label} scrolls the document sideways"
      assert_operator overflow["main"], :<=, 1, "#{label} scrolls its main content sideways"
    end

    def create_transaction(name, date, amount, category: nil, merchant: nil, tags: [], account: nil)
      account ||= accounts(:depository)

      account.entries.create! \
        name: name,
        date: date,
        amount: amount,
        currency: "USD",
        entryable: Transaction.new(category: category, merchant: merchant, tags: tags)
    end

    def transaction_checkbox(transaction)
      find("#" + dom_id(transaction, "selection"), visible: :all)
    end
end
