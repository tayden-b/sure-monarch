# Monarch Parity Audit — Sure on `monarch-baseline`

Purpose: precise audit of where Sure stands vs the owner's Monarch Money usage, so Wave-2 workers can be dispatched on independent, PR-sized tasks. Read with `docs/monarch-import/SCHEMA.md` and `docs/monarch-import/IMPORT-RULES.md`.

Method: ran the app in the devcontainer (`bin/dev`, Puma + Sidekiq, Postgres + Redis), loaded `bin/rake demo_data:default` (Demo Family, ~8.4k transactions, 9 goals, multi-currency), logged in as `user@example.com`, clicked through every nav surface at desktop width and at ~420px (phone) width, and read the models/controllers/routes behind each surface. Statuses: **exists** = functionally on par or better; **partial** = the capability exists but a real Monarch behavior is missing; **missing** = no meaningful equivalent.

## 1. Summary table

| # | Capability | Status | Size to parity | Biggest gap |
|---|-----------|--------|----------------|-------------|
| 1 | Accounts overview (grouped balances, hidden/deactivated, net worth + daily chart, asset/liability) | Partial | M | Monarch's 4 per-account visibility flags (`hideFromList`, `includeInNetWorth`, `hideTransactionsFromReports`, `hideInBudget`) map to only 2 Sure concepts (`status` + `exclude_from_reports`); no hide-from-list-but-counted state |
| 2 | Unified transactions feed (search/filter/bulk/categorize/tag/hide/needs-review/pending/merchant cleanup/transfers) | Partial | L | No first-class "needs review" flag or review queue; cross-provider duplicate detection is pending-vs-posted and same-account only |
| 3 | Categories & category groups + rules engine | Partial | M | Categories have no income/expense/transfer classification (removed upstream); rules have no priority ordering |
| 4 | Recurring / subscription detection + upcoming view | Exists | — | Detection, suggestions, occurrences, upcoming tab all present; `/bills` is preview-gated |
| 5 | Investments (holdings per account, aggregate holdings, cost basis/gain, allocation) | Partial | M | No aggregate holdings view across accounts; no allocation-by-asset-class view |
| 6 | Cash flow & spending reports (income vs expenses, by category, by merchant, savings rate) + budgets (category + flex) | Partial | M | No by-merchant report; no flex/discretionary budget concept |
| 7 | Mobile-browser UX | Partial | M | Responsive shell + bottom nav + PWA exist; transactions list and filters are desktop-oriented |
| 8 | Data hygiene (dup detection feed + imports, import revert) | Partial | M | Import revert exists for CSV/QIF/etc.; Monarch archive importer doesn't exist yet (Wave-1 scope); cross-source dedup unverified |
| — | Monarch archive import | Missing | L | No `MonarchImport` type, no `import/*.json`/`monarch.sqlite` readers |

## 2. Per-capability detail

### 2.1 Accounts overview — **Partial** (M)

Monarch want: ~25 accounts in one clean view grouped by type (cash, credit, investments incl. 401k/IRA/HSA/pension, crypto), hidden/deactivated respected, net worth total + daily history, asset vs liability split.

What exists:

- `/accounts` (`accounts_controller#index`, `app/views/accounts/index.html.erb`, `_account_groups`, `_accountable_group`, `_account`) lists every account grouped first by provider item (e.g. "Apple Wallet", "Other accounts") then by accountable type (Credit Cards, Cash, Crypto, Investments, Loans, Other Assets, Other Liabilities, Properties, Vehicles) with per-group totals and per-account subtype labels (`account.long_subtype_label`, e.g. "401(k)", "Roth IRA", "HSA").
- Account lifecycle: `aasm` states `active`/`draft`/`disabled`/`pending_deletion` (`account.rb`); `scope :visible` / `:historical`; `accounts#toggle_active` and `toggle_exclude_from_reports`. Disabled ≈ Monarch "deactivated"; `exclude_from_reports` ≈ `hideTransactionsFromReports`.
- Investment subtypes are rich: `Investment::SUBTYPES` covers 401k, Roth 401k, 403b, 457b, TSP, IRA, Roth IRA, SEP/SIMPLE IRA, 529, HSA, UGMA/UTMA, plus UK/CA pension types, each mapped to `tax_treatment` (`taxable`/`tax_deferred`/`tax_exempt`/`tax_advantaged`) — that is strictly richer than Monarch.
- Net worth: dashboard "Net Worth" section + `BalanceSheet#net_worth_series` (daily series from `balances`/`entries`), All/Assets/Debts tabs, Balance Sheet section with Assets/Liabilities breakdown by group, plus an accounts sidebar.

Gaps:

- Monarch's per-account flags are independent: `hideFromList` (hide in lists but still count), `includeInNetWorth`, `hideTransactionsFromReports`, `hideInBudget`, `deactivatedAt`. Sure has only `status` (disabled hides + stops sync) and `exclude_from_reports`. There is no "hidden from account list but included in net worth" state, and no per-account budget exclusion — the importer (Wave-1) will need somewhere to put these flags (likely `accounts.flags`/`settings` JSONB or new columns).
- Grouping is connection-first, not type-first: Monarch shows one flat list grouped by type across institutions; Sure nests under each provider item. With 25 accounts spanning several institutions this reads busier than Monarch.
- No institution-level subtotal/rollup in the type groups.
- UX: `/accounts` lives under the Settings-style layout (tab bar at top on mobile, sidebar in settings on desktop), not as a primary nav destination — Monarch puts accounts front-and-center. First cold render was ~12s; ~3.5s warm (acceptable but worth noting).
- Broken/quirk: demo data shows "Marcus High-Yield Savings" at **−$36,273.00** (a savings account with a large negative balance — demo fixture oddity, not necessarily a bug) and "Vanguard 401(k)" at $0.00.

Dependencies: account flag schema work feeds the Monarch importer's account mapping (Wave-1) and the accounts-page grouping changes (Wave-2).

### 2.2 Unified transactions feed — **Partial** (L)

Monarch want: one feed across all cards/banks with search; filter by account/category/merchant/tag/date/amount; bulk edit; categorize; tag; hide-from-reports; needs-review queue; pending handling; merchant name cleanup; transfer detection/pairing.

What exists (`/transactions`, `TransactionsController`, `Transaction::Search`, `app/views/transactions/`):

- Search by name; filter drawer with Account, Date, Type, Status (pending/confirmed), Amount (operator + value), Category (incl. synthetic "Uncategorized" sentinel `Category::UNCATEGORIZED_FILTER_VALUE`), Tag, Merchant (incl. "No merchant" sentinel), AI status. `active_accounts_only` hides disabled accounts' txns.
- Date-grouped list w/ daily totals, per-row inline category editor, tags column, pending badges, auto-matched transfer rows with confirm/reject (`_transfer_match`), bulk checkboxes → selection bar → bulk update (`Transactions::BulkUpdatesController`), bulk delete (`BulkDeletionsController`), guided categorize wizard (`Transactions::CategorizesController` + `transactions/categorizes`), search save (`searches_controller`).
- Transaction dialog: exclude from reports (`entries.excluded`), one-time expense, splits (`SplitsController`), manual transfer matcher, mark-as-recurring, convert-to-trade, merge_duplicate/dismiss_duplicate, delete, merchant/tag/notes/attachments editing.
- Pending: provider pending flags in `transactions.extra` (`Entry.pending`/`excluding_pending` scopes across `Transaction::PENDING_PROVIDERS`), stale-pending auto-exclusion (`Entry.auto_exclude_stale_pending`), retro reconcile (`Entry.reconcile_pending_duplicates`), and `PendingDuplicateMergesController` UI for merging a pending txn into a posted one.
- Transfers: `Transfer` model pairs inflow+outflow (`TRANSFER_KINDS`), auto-match window + `TransferMatchesController` for manual pairing; totals in `Transaction::Search#totals` exclude transfer kinds and tax-advantaged accounts.
- Merchants: `Merchant`/`FamilyMerchant` + `/family_merchants` page (merge + AI enhance routes), `SetTransactionMerchant`/`AutoDetectMerchants` rule executors.

Gaps:

- **No needs-review state.** Monarch has an explicit "needs review" flag + review queue (auto-flag on import, manual mark/unmark, filtered feed). Sure's closest is the uncategorized count + `uncategorized` filter — different semantic (a categorized txn can still need review; Monarch flags provider mismatches). Needs a `transactions.needs_review`-style flag (or `entries` column), queue filter, and bulk mark-reviewed.
- **Merchant cleanup is partial.** FamilyMerchant rename/merge exists, but Monarch's "recurring name cleanup" (e.g. `AMAZON.COM*ABC123` → Amazon applied retroactively) maps to rules with `transaction_name like` + set-merchant — works, but there's no merchant-name normalization helper or dedup of near-identical merchant spellings.
- **Cross-provider duplicate detection**: `pending_duplicate_candidates` and `reconcile_pending_duplicates` are same-account, pending-vs-posted only. Monarch archive import will create dupes across provider feeds and imported history (e.g. the same charge on an imported Monarch txn AND a live feed). No cross-account/cross-source dedup candidate list exists — transfer matching is the only inter-account mechanism.
- UX: the feed is a desktop table (checkbox column, multi-column rows, hover menus); usable on phone but filter drawer + bulk bar are cramped at 420px.

Dependencies: needs-review flag → rules engine + importer; cross-source dedup → importer output + transfer matcher UI.

### 2.3 Categories & rules — **Partial** (M)

Monarch want: category groups + categories, typed income/expense/transfer; rules with merchant-contains / amount criteria → set category / add tags, **ordered**, apply-to-existing.

What exists:

- `/categories`: `Category` is a 2-level tree (`parent_id`, roots + one level of subcategories), color + lucide icon, `last_used_at`, subcategory rollup into parent for budgets/reports. **Income/expense classification was removed upstream** — `scope :incomes`/`:expenses` now return `all`; there is no category-group entity and no transfer-typed category (transfers are `transactions.kind`-based, not category-based).
- `/rules`: `Rule` (name, `resource_type`, `active`, `effective_date`) → `Rule::Condition` (incl. compound sub-conditions) → `Rule::Action`; `RuleRun` audit trail. Condition filters (`Rule::Registry::TransactionResource::CONDITION_FILTER_CLASSES`): transaction name, amount, type, merchant, category, tag, details, notes, account. Executors: set category/tags/merchant/name, investment activity label, exclude, set-as-transfer/payment, email notify, and LLM-gated auto-categorize / auto-detect-merchants. `confirm`/`apply` and `confirm_all`/`apply_all` implement apply-to-existing with a count preview (`affected_resource_count`); scope = family transactions from `effective_date` on. `create_from_grouping` gives quick rule creation.

Gaps:

- **No category groups / classification.** Monarch's groups are typed (income / expense / transfer) and drive reports; Sure's parent categories are untyped. A Monarch import needs a place for the group name and the income/expense/transfer kind (e.g. a `category_groups` table or `categories.parent + classification` re-add). This is the single most structural gap for the import.
- **No rule ordering.** `rules` table has no `position`/`priority` column — index sorts by name/updated_at only. All matching rules apply; conflicting actions (two rules setting category) resolve in an unspecified order. Monarch executes rules in user-defined order, first-wins-ish.
- No "merchant contains" convenience: covered by `transaction_name like` and `transaction_merchant` conditions — fine, but Monarch's merchant-field-contains maps most naturally to name contains.
- Rules run on `effective_date..` scope — no way to bound an apply-to-existing by end date.

Dependencies: classification re-add touches categories, budgets, reports, rules — sequence it early (Wave-2 task 1) before the importer maps Monarch groups.

### 2.4 Recurring / subscriptions — **Exists**

Monarch want: recurring/subscription detection + upcoming view.

- `/recurring_transactions`: `RecurringTransaction` + detection pipeline — "Identify Patterns" on demand, auto-runs after imports and provider syncs; "Possible new bills" suggestion list with Add bill / Not a bill (confirm/dismiss); enable toggle; `recurring_occurrences` with mark_paid/skip/reopen; expected-spend fields (amount, frequency, merchant, account).
- Transactions page "Upcoming" tab (`_upcoming`) shows projected next occurrences inline with the feed.
- `/bills` surface exists but is **preview-feature gated** (redirects to recurring page without the flag) — bills calendar + ICS feed live behind `Feature` preview.
- Quirk: the suggestions list showed obvious duplicates (e.g. two "Auto Loan Payment $413.15 · Monthly on the 1st" rows, two "Student Loan Payment" rows) — either a dedup hole in the detector or demo-data artifact worth a look by whoever owns recurring.

Minor gaps vs Monarch: Monarch shows a subscription-centric "Merchants → recurring" rollup and renewal reminders; Sure's equivalent is the recurring list + upcoming tab. Fine.

Size: — (exists). Optional polish task listed in Wave-2.

### 2.5 Investments — **Partial** (M)

Monarch want: holdings per account, aggregate holdings across accounts, cost basis/gain, allocation.

What exists:

- Per-account holdings: `HoldingsController#index?account_id=` + `Holding` (qty, `avg_cost`, `trend`, `day_change`, `weight`, manual/`set_manual_cost_basis!`, `unlock_cost_basis!`, `remap_security!`, `reset_security_to_provider!`, `cost_basis_known?`, source priority); `TradesController` + `Trade` entries w/ activity labels.
- Securities: `Security` w/ `asset_class`/`asset_sub_class` columns + `classification_locked`/`classification_source` (schema line 2285+) — the data model for allocation already exists; nothing renders it.
- Dashboard "Investments" section: aggregate total, total return, top holding table, 30-day contributions/withdrawals/trades counts (`pages/dashboard/_investment_summary`).
- Reports "Investment performance" section: gains by tax treatment, top holdings.
- Gains/losses: `Holding#trend`/`day_change`; no realized-gain report, no per-lot view.

Gaps:

- **No aggregate holdings view.** Monarch's Holdings page collapses the same security across all accounts (total qty/value/return, drill into per-account lots). Today holdings are strictly per-account; the dashboard widget shows only the top holding.
- **No allocation view.** `asset_class`/`asset_sub_class` columns exist on `securities` but there's no allocation chart (by class, or by holding weight across the family) anywhere; dashboard shows weights within investments but not a standalone breakdown.
- Cost-basis UX exists per holding but Monarch also surfaces account-level and portfolio-level unrealized gain totals; only per-holding and report-level pieces exist.
- UX: holdings tab inside the account page is fine on desktop; on phone the table overflows horizontally.

Dependencies: aggregate/allocation reads should reuse `Security` classification + `Holding` scopes; nothing schema-blocking — the Monarch importer will want `holdingsCount`/holdings mapping handled separately (Wave-1).

### 2.6 Cash flow, reports & budgets — **Partial** (M)

Monarch want: monthly income vs expenses, by category, by merchant, savings rate; category + flex budgets.

What exists:

- `/reports` (`ReportsController`, `IncomeStatement::*`): Monthly/Quarterly/YTD/Last-6-Months/Custom periods; income / expenses / net-savings / budget-performance cards; month-by-month breakdown incl. savings rate; Activity Breakdown **by category** (parent-rolled); net worth + investment performance sections; CSV export + Google Sheets + print.
- Cash flow: `IncomeStatement::CashFlow`/`CashFlowGraph`/`Sankey`, `CashFlowsController` (dashboard sankey widget "money flow"), plus Money In/Out and Spending dashboard cards.
- `/budgets/:month` (`BudgetsController`, `Budget`/`BudgetCategory`): per-category budgets with subcategory rollup (e.g. Rent under Housing), expected income vs budgeted income, over/on-track/near-limit states, per-day remaining suggestion, Budgeted/Actual tabs, `copy_previous` route, budget performance on reports.

Gaps:

- **No by-merchant breakdown** — Activity Breakdown is category-only; Monarch shows top merchants with spend. `transactions.merchant_id` join makes this an S task.
- **No flex/discretionary budget.** Monarch's flex number = total non-fixed spend pool; Sure budgets are strictly category-scoped (plus expected income). A family-level "everything else" budget line needs a `Budget`-level concept, not a category — probably a synthetic budget row over uncategorized/unbudgeted categories. M.
- No budget rollover/carryover handling (Monarch flex budgets are month-scoped, so parity is OK without it).
- Reports' category breakdown doesn't include transfers/investments segments the way Monarch's cash-flow does; sankey covers most of that.

Dependencies: none blocking; by-merchant view touches `IncomeStatement` + reports views.

### 2.7 Mobile-browser UX — **Partial** (M)

Monarch want: phone is the primary way to check balances/transactions.

What exists:

- Responsive app shell (`layouts/application.html.erb`): left sidebar collapses to a hamburger + slide-over, **bottom nav on mobile** (`lg:hidden fixed bottom-0`) with Home/Transactions/Reports/Budgets (+ Assistant).
- **PWA**: `PwaController` serves `manifest` + `service-worker`; installable to home screen.
- Settings pages render as a single-column settings layout with a top tab bar on narrow screens — verified at ~420px width.

Gaps:

- Transactions list is a multi-column desktop table: at 420px rows show checkbox + merchant + amount but the tag column, hover "…" menu, and bulk-selection bar are cramped; filter drawer is a side sheet that crowds the viewport. A mobile-first pass on `_transaction` rows + selection bar + filter sheet is needed.
- Dashboard sections stack but charts (net worth, sankey, donut) are desktop-sized; no mobile-tuned chart heights.
- `/accounts` page is a settings-layout page — fine but long-scroll; Monarch mobile foregrounds account balances.
- No mobile quick-add or swipe actions (Monarch mobile allows mark-reviewed/categorize swipes).
- Bottom nav has no Accounts entry — accounts reachable only via Home sidebar groups on mobile.

Dependencies: none; pure view/stimulus work.

### 2.8 Data hygiene — **Partial** (M)

Monarch want: duplicate detection across provider feed + imported history; import revert.

What exists:

- `Import` STI framework (`import.rb`, `import/*_mapping`, `preflight`, `row`): statuses incl. `reverting`/`revert_failed`, `Import#revert`/`revert_later` with `revert_derived_state!`, stuck-import reaper (`Import.clean`, `PRESUMED_LOST_AFTER`), `publish`/`publish_later`, row-level mapping UI (`rows`/`mappings`), summary page, cancel. CSV/QIF/PDF/Sure/Actual/YNAB import types exist.
- Pending-vs-posted dedup: same-account candidate search (`pending_duplicate_candidates`), manual merge UI (`PendingDuplicateMergesController`), `merge_duplicate`/`dismiss_duplicate` on transactions, retro `reconcile_pending_duplicates(dry_run:)`, auto-exclusion of stale pendings.
- `Account::ProviderImportAdapter` + `family_merchants` merge — dedup primitives exist.

Gaps:

- **No cross-source duplicate pass.** Importing Monarch history next to live provider feeds will create dupes the current machinery (same-account, pending-only) won't catch. Need a post-import dedup candidate list: same account OR cross-account, amount+date±window+merchant-similarity, merge-or-dismiss UI — can reuse `PendingDuplicateMergesController` shape.
- Import revert exists but only for the generic import pipeline; Monarch import must implement `revert_derived_state!` for its own artifacts (accounts, balance history, holdings) — Wave-1 concern, flagged so the dedup task can build on it.
- No "unmerge"/audit trail for a wrong merge (transfer confirm is reversible; duplicate merge is not obviously reversible).

Dependencies: Wave-1 importer must tag imported entries with provenance (`entries.source`/import_id or plaid_id mapping) so dedup can prefer provider rows over imported ones.

## 3. Wave-2 work breakdown

Ordered so no two tasks touch the same hot files; each is an independent PR against `monarch-baseline`. Tasks marked (I) assume the Wave-1 Monarch importer exists; if not, they can still land independently (dedup works on any entries).

**T1 — Category classification + groups (M, structural, do first).**
Add `categories.classification` (income/expense/transfer) + `categories.group_name` (or a `category_groups` table) so Monarch's typed groups map cleanly. Re-introduce typed scopes, show type on the categories page, use classification in reports/budgets instead of sign-only inference.
*Acceptance:* categories carry income/expense/transfer type; `/categories` groups by group; IncomeStatement uses classification where appropriate; migration backfills existing roots (Income → income, others → expense).
*Files:* `app/models/category.rb`, `db/migrate/*`, `app/views/categories/*`, `app/controllers/categories_controller.rb`, `app/models/income_statement/*`, `config/routes.rb` (only if group routes added), `config/locales/**`, tests under `test/models` + `test/controllers`.

**T2 — Needs-review queue (M).**
Add a `needs_review` (or `review_state`) flag on transactions/entries with bulk mark-review/unmark, a "Needs review" filter + badge next to Uncategorized, auto-set on new provider/import rows (configurable), and a per-row "Mark reviewed" action.
*Acceptance:* feed filter + queue; bulk action; rule executor optional; importer can set it.
*Files:* `db/migrate/*`, `app/models/entry.rb`, `app/models/transaction.rb`, `app/models/transaction/search.rb`, `app/controllers/transactions_controller.rb`, `app/controllers/transactions/bulk_updates_controller.rb`, `app/views/transactions/*`, `app/models/rule/registry/transaction_resource.rb`, tests.

**T3 — Cross-source duplicate detection (L).**
Generalize `pending_duplicate_candidates` into a family-level duplicate candidate service (same-account + cross-account, amount/date±window/merchant-similarity, source-preference ordering), reuse the pending-merge UI for review/merge/dismiss, and run it as a post-import/post-sync step. (I)
*Acceptance:* candidate list UI grouped by account; merge transfers entries correctly and clears `needs_review`; dry-run output visible; importer triggers a scan after publish.
*Files:* new `app/services/dedup/*` or `app/models/entry/duplicate_candidates.rb`, `app/controllers/pending_duplicate_merges_controller.rb` (or a sibling controller), `app/models/import.rb` (hook only), `app/views/…`, tests.

**T4 — Rule ordering (S).**
Add `rules.position` (or `priority`) with drag/order UI on `/rules`, apply rules in order, and define/choose first-match-wins vs all-match semantics explicitly.
*Acceptance:* rules list reorderable; order persisted; `Rule.apply` runs in order; test covers two conflicting rules.
*Files:* `db/migrate/*`, `app/models/rule.rb`, `app/controllers/rules_controller.rb`, `app/views/rules/*`, `app/javascript/controllers/*` (sortable), tests.

**T5 — Aggregate holdings + allocation view (M).**
New `/holdings` (family-level) page: aggregate same-security positions across accounts with total qty/value/avg-cost/return, per-account drill-down, plus an allocation section grouped by `securities.asset_class`/holding weight.
*Acceptance:* page lists every security held by the family rolled up; allocation chart/table totals to 100%; links into per-account holdings.
*Files:* `app/controllers/holdings_controller.rb` (new family-scope index) or new `PortfolioController`, `app/models/holding.rb` (scopes), `app/models/security.rb`, `app/views/holdings/*`, `config/routes.rb`, tests.

**T6 — Merchant spend report + reports polish (S).**
Add a "by merchant" breakdown (top-N merchants w/ spend + txn links) alongside Activity Breakdown on `/reports`, reusing `IncomeStatement` rollups.
*Acceptance:* merchant breakdown for selected period; respects excluded txns; CSV includes it.
*Files:* `app/models/income_statement/*`, `app/controllers/reports_controller.rb`, `app/views/reports/*`, tests.

**T7 — Flex/discretionary budget (M).**
Add a family-level "spending budget" per month covering all expense txns not already in a category budget (Monarch flex), rendered as a distinct card on `/budgets`.
*Acceptance:* flex amount editable per month; actual = unbudgeted-category outflows; shows in budget performance.
*Files:* `app/models/budget.rb`, `app/models/budget_category.rb` (or new `BudgetFlex`), `app/controllers/budgets_controller.rb`, `app/views/budgets/*`, `db/migrate/*`, tests.

**T8 — Mobile transactions UX pass (M).**
Phone-first polish of `/transactions` list rows, filter sheet, bulk-selection bar, and transaction dialog; tighten dashboard chart heights; add Accounts to bottom nav or home sidebar quick-access.
*Acceptance:* 420px viewport: one-thumb categorize/exclude/tag; filter sheet full-height; no horizontal overflow on any audited page.
*Files:* `app/views/transactions/*`, `app/views/layouts/application.html.erb` (nav items only), `app/views/pages/dashboard/*` (chart wrappers), stimulus controllers, system tests.

**T9 — Accounts overview parity (M).**
Type-first grouping option on `/accounts` (flatten provider grouping behind a section), implement Monarch's visibility flags (`hide_from_list`, `include_in_net_worth`, `hide_transactions_from_reports`, `hide_in_budget`) backed by `accounts.flags` or columns, and surface institution name + subtype in rows.
*Acceptance:* hidden-from-list accounts excluded from lists but counted in net worth; each flag maps to documented behavior; importer can set them.
*Files:* `db/migrate/*`, `app/models/account.rb`, `app/controllers/accounts_controller.rb`, `app/views/accounts/*`, `app/models/balance_sheet.rb` / `income_statement` (flag plumbing), tests.

**T10 — Recurring polish (S, optional).**
Dedup "Possible new bills" suggestions (same merchant+amount+frequency), expose `/bills` behind preview flag decision, and surface subscription totals.
*Acceptance:* no duplicate suggestions; a monthly subscriptions total is shown.
*Files:* `app/models/recurring_transaction*`, `app/controllers/recurring_transactions_controller.rb`, `app/views/recurring_transactions/*`, tests.

**File-collision check:** T1 owns `category.rb` + income_statement internals; T6 only *adds* to `income_statement` — sequence T6 after T1 or have it read classification only. T2 owns `transaction.rb`/`search.rb`/`bulk_updates`; T3 works on new dedup service + merge controller — independent. T5 owns `holding.rb`/`holdings_controller`; T9 owns `account.rb`/`accounts_controller` — independent. T4 owns `rule.rb`/`rules_controller` — T2's rule-executor hook is additive; sequence T4 before T2 or keep T2's executor a no-order change. T8 touches only views — safe alongside anything.

## 4. Broken UI / quirks found (demo data)

- `/bills` redirects to `/recurring_transactions` — preview feature gated; fine, but note the nav link still renders.
- Recurring "Possible new bills" showed duplicate suggestions (same name/amount/frequency listed twice).
- "Marcus High-Yield Savings" displays −$36,273.00 (negative savings balance); "Vanguard 401(k)" $0.00 — likely demo fixture artifacts.
- "Missing historical data" warning banner is permanent without market/exchange-rate providers configured (expected on self-host, but noisy for a one-user setup).
- `/accounts` first cold render ~12s (then ~3.5s); `/reports` ~4.6s — worth a perf pass later, not parity-blocking.
- AI features (chats, auto-categorize executors) need `OPENAI_ACCESS_TOKEN` — disabled in demo; Monarch parity doesn't require them but rules' AI executors degrade silently.

## 5. Out of scope / follow-ups

- Monarch archive import itself (the whole `import/*.json` + `monarch.sqlite` pipeline) is Wave-1 scope, tracked by `docs/monarch-import/*`; this audit only sized the surfaces it lands in.
- Goals, assistant/AI chat, API keys, Statement Vault, provider connections (Plaid sandbox) — not part of the 8 capabilities.
- Realized-gain / per-lot cost basis reports — Monarch doesn't have them either; skipped.
