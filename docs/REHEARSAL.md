# Integration Rehearsal Report

End-to-end rehearsal of the Monarch Money replacement on a clean machine:
`deploy/mac` kit → account onboarding → synthetic archive import → every parity
surface → Plaid smoke → backup/restore. Run on this worker's Linux VM as the
Linux-equivalent of the Mac run; Mac-only steps are called out explicitly.

Environment: `monarch-baseline` @ `fe7f8cc4`, Docker Compose stack
(`deploy/mac/docker-compose.yml`, project `mac`), Ruby 3.4.9 / Rails 8 /
Postgres 18 / Redis, rehearsed at `http://localhost:3000` on 2026-10-25.

**Verdict: the build works end-to-end.** Two real defects found and fixed;
residual items that need Tayden's hands are listed at the end.

---

## Phase 1 — deploy kit from scratch

**Result: PASS after one fix.**

`cd deploy/mac && ./bin/setup-mac` ran to completion on Linux:

- `docker`/`docker compose` checks, `.env` generation (secrets auto-generated),
  compose image build, `web`/`worker`/`db`/`redis` up, `db:prepare`, `/up` wait.
- `http://localhost:3000/up` healthy; signed up `rehearsal@example.com`,
  completed the 3-step onboarding wizard (profile → preferences → goals),
  `Rehearsal Family` created with `onboarded: true`.

### Finding 1 — `setup-mac` raced the web entrypoint's `db:prepare` (FIXED)

On the first clean run the script died at "Preparing the database" with:

```
PG::DuplicateObject: relation "fk_rails_5dd7c0e0b5" already exists
```

The web container's entrypoint runs `bin/rails db:prepare` before Puma boots
(`bin/docker-entrypoint`), while `setup-mac` also ran
`docker compose exec -T web bin/rails db:prepare` *before* waiting on `/up`.
On a fresh DB both prepares run `schema:load` concurrently → duplicate FK name.

This would fail on Mac too — same race, independent of platform.

**Fix** (`24677fd1`): `deploy/mac/bin/setup-mac` now waits for `/up` to be
healthy *before* running its own `db:prepare` — a healthy app means the
entrypoint's prepare already finished, so the script's prepare is a safe no-op.
The health-wait loop was also lengthened (60 → 90 × 1 s). Verified with a full
clean-slate re-run (`docker compose down -v`, fresh `.env`): setup completes.

### Demo data decision

No `Demo::Generator` entry point exists for production; `db:prepare` seeds only
the Doorkeeper OAuth app (no demo families — verified after a clean rebuild).
The Monarch archive import below provides the realistic data; no demo seeding
was added.

### Linux adaptations / Mac-only steps

- Everything in `setup-mac` worked on Linux as written (bash + docker).
- Tailscale/launchd steps are Mac-only by nature and were not rehearsed —
  flagged in residual items.

### Gotcha found while working in the container (documented, not a kit bug)

`POSTGRES_DB` is `sure_production` for **all** Rails envs in the container, so
`-e RAILS_ENV=test bin/rails test` writes fixture data into the production DB.
Run the test suite on the host or with `-e POSTGRES_DB=sure_test`
(this is how the green importer run below was produced).

## Phase 2 — synthetic archive import + reconciliation

**Result: PASS after one fix.**

```
cp -r test/fixtures/files/monarch_archive/ deploy/mac/data/archive/
docker compose exec -T web bin/rails "monarch:import[/archive,dry_run]"
docker compose exec -T web bin/rails "monarch:import[/archive]"
```

Dry run wrote nothing and printed the same report shape as the real run.

### Reconciliation report (real run)

```
collection               archive created updated skipped
--------------------------------------------------------
category_groups                3       3       0       0
categories                     8       8       0       0
tags                           2       2       0       0
accounts                      12      12       0       0
merchants                      3       6       0       0
goals                          1       1       0       0
transaction_tags               2       2       0       0
transactions                   8       8       0       0
balance_history                7       7       0       0
holdings                       3       3       0       0
rules                          3       3       0       0
recurring_streams              2       2       0       0
budget_totals                  2       1       0       1
  └─ future_month: 1
budget_months                  4       2       0       2
  └─ unsupported_scope:group: 1
  └─ future_month: 1
settings_documents             2       0       0       2
  └─ reference_only: 2
credit_scores                  2       0       0       2
  └─ reference_only: 2
aggregate_holdings             1       0       0       1
  └─ derived_or_not_applicable: 1
attachments                    0       0       0       0
equity_grants                  0       0       0       0
net_worth_daily                1       0       0       1
  └─ derived_or_not_applicable: 1
portfolio_performance          1       0       0       1
  └─ derived_or_not_applicable: 1
provenance                     2       0       0       2
  └─ derived_or_not_applicable: 2
tax_lots                       0       0       0       0
transaction_activity           1       0       0       1
  └─ derived_or_not_applicable: 1
```

Every collection's `created`+`updated`+`skipped` equals its archive count.
`skipped` reasons are sane (future-month budgets, group-scope budgets,
reference/derived-only collections). `merchants created=6 > archive=3` is
legitimate: `monarch_merchant_for` creates stub merchants for merchant ids
referenced by transactions but absent from `merchants.json`.

Per-account transaction totals: all diffs `0.0` (report prints Sure's
positive=expense convention against the archive's signed totals).

### Finding 2 — accounts without `balance_history` imported with balance 0 (FIXED)

The importer only wrote reconciliation `Valuation` entries for
`balance_history` rows. `Balance::Materializer` (forward strategy) then
recomputed each account from its opening anchor — which an account with no
entries lacks (defaults to today, seed 0) — and overwrote the imported
`signedBalance` with `0`. **8 of 12** fixture accounts were zeroed:

| Account | signedBalance | after import (before fix) |
|---|---|---|
| Work 401k | 80,000 | 0 |
| Traditional IRA | 15,000 | 0 |
| Roth IRA | 9,000 | 0 |
| Health Savings | 4,100 | 0 |
| Old Pension | 21,000 | 0 |
| Old Joint Card (liability) | −200 | 0 |
| Side Savings (hidden) | 500 | 0 |
| Coinbase | 3,200 | 0 |

**Fix** (`24677fd1`): after `import_balance_history`, the importer now writes
one `kind: "reconciliation"` valuation at `Date.current` for every imported
account that has no valuation entries (idempotent via
`external_id="anchor:<monarch_id>"`). Anchors are not counted in the report so
`balance_history` counts keep matching the archive's row count. Covered by the
new test `"accounts without balance history keep their signed balance after
materialization"` (includes a re-import no-duplicate assertion).

Verified on the running stack: **all 12 accounts reconcile to the archive's
`signedBalance` exactly** (liabilities stored positive per convention):

```
Coinbase               3200.0   Roth IRA             9000.0
Emergency Savings     12000.0   Side Savings (Hidden) 500.0
Everyday Checking      5230.5   Taxable Brokerage    25000.0
Health Savings         4100.0   Traditional IRA      15000.0
Old Joint Card          200.0   Work 401k            80000.0
Old Pension           21000.0   Rewards Card          1450.75
```

W2-F cash split: Taxable Brokerage `balance = cash_balance = 25,000` and the
500 cash-position holding imports as a `kind: "cash"` holding row — matching
the pinned semantics (cash holdings fold into cash, never on top of the
valuation total).

### `monarch:dedup`

With only the archive's 8 transactions, the scanner reports 0 pairs — no URL
prints (by design: the task only prints the candidates URL when `total > 0`).
After inserting a synthetic duplicate (same amount, +1 day), the task printed:

```
1 duplicate candidate pair(s) (+/-3d window, cap 200):
  high confidence: 1
  Everyday Checking: 1 pair(s)
Review and merge at http://localhost:3000/dedup/candidates
```

### needs_review pipeline

`txn-4` (`needsReview: true` in the archive) imports flagged → the
`/transactions` "Needs review (1)" chip and filter work. `hideFromReports`
(`txn-7`) maps to `exclude_from_reports`. `IMPORT_AUTO_FLAG_NEEDS_REVIEW`
(documented in `.env.example`) is unset → only archive-sourced flags apply.

## Phase 3 — parity surfaces (1280px + 412px)

**Result: PASS — everything renders and behaves correctly.**

Screenshots live in `docs/rehearsal/` (`d-*` desktop, `m-*` mobile).

| Surface | Result |
|---|---|
| `/accounts` (by type) | Type-grouped list; all balances correct; Investments subtotal $154,100 ✓ |
| `/accounts?view=connections` | Renders; `hide_from_list` accounts hidden in both views while `include_in_net_worth` ones still count ($173,579.75 net worth = archive totals exactly) |
| `/transactions` | Unified feed incl. imported monarch rows (9 shown: 8 imported + 1 synthetic dup); mobile bottom-nav layout fine |
| Needs-review queue | `?q[review_status][]=needs_review` shows the 1 flagged txn with badge; toggle via detail page works both ways (POST `toggle_review`, 200; count 1→0→1) |
| `/dedup/candidates` | Pair card renders with confidence + KEEP/REMOVE; **merge executed** (monarch row merged into manual keeper, 8→7 monarch txns, 0 pairs left); second pair **dismissed** (`Dedup::Dismissal` persisted, 0 pairs) |
| `/categories` | Imported CategoryGroups render ordered (EVERYDAY EXPENSES·4·EXPENSE, INCOME·2, TRANSFERS·2) with member categories |
| `/budgets/sep-2026` | Flex card works end-to-end: set flex to $150 → "$15.99 spent / $134.01 left"; imported category budgets show spent/budgeted/remaining from imported txns |
| `/reports` (Sep 2026) | Income $2,450 / expenses / savings rate / net-worth section / category+merchant breakdown all render |
| CSV export | `export_transactions.csv` downloads; contains INCOME, EXPENSES and the **SPENDING BY MERCHANT** section (sample in `docs/rehearsal/reports-export-sample.csv`) |
| `/rules` | Reordering persists — moved "Monarch rule 0: grocery" down; positions saved (rule 0 ⇄ rule 1 swap verified in DB). Drag handle, keyboard (Enter/grab → arrows → Enter), and chevron buttons all present |
| `/recurring_transactions` | Imported recurring streams (Streamflix etc.) listed |
| `/holdings` | Aggregate holdings surface renders; imported holdings (AAPL, BTC, cash sleeve) present |
| Dashboard `/` | Net-worth chart + accounts summary render post-import |

No rendering defects found; nothing required a UI fix.

## Phase 4 — Plaid Sandbox smoke

**Result: SKIPPED by design — Tayden must supply keys.**

```
$ bin/rails plaid:sandbox_smoke
SKIPPED: PLAID_CLIENT_ID / PLAID_SECRET are not set.
  Get free Sandbox keys at https://dashboard.plaid.com/developers/keys,
  set PLAID_CLIENT_ID, PLAID_SECRET and PLAID_ENV=sandbox, then re-run.
```

The task exits 0 on missing credentials and **refuses** to run unless
`PLAID_ENV=sandbox` (it can never touch a real Plaid env). With keys it creates
a link token, builds a Sandbox Item, syncs accounts/transactions/holdings, and
rolls back all DB writes. Nothing was stubbed.

## Phase 5 — backup/restore

**Result: PASS.**

- `./bin/backup` → `backups/sure-20261025-222321.dump` (523 KB, `pg_dump -Fc`,
  refuses empty dumps, retains 14).
- `./bin/restore` (accepts `restore` on stdin) → `pg_restore --clean
  --if-exists` over the live DB.
- Row counts identical across restore: `accounts=12, entries=24, users=1,
  balances=70`; `/up` healthy and `/accounts` renders after restart.

## Findings summary

| # | Severity | What | Fix |
|---|---|---|---|
| 1 | High (blocks fresh install) | `setup-mac` raced entrypoint `db:prepare` → `PG::DuplicateObject` | Wait on `/up` before the script's own prepare (`24677fd1`) |
| 2 | High (data correctness) | Accounts with no `balance_history` imported as balance 0 | Anchor reconciliation valuation per imported account (`24677fd1`) |

## Test evidence

- `docker compose exec -T -e RAILS_ENV=test -e POSTGRES_DB=sure_test web bin/rails test test/models/monarch/importer_test.rb` → **22 runs, 165 assertions, 0 failures, 0 errors, 0 skips** (includes the new anchor test; must run against a real `sure_test` DB — see Phase 1 gotcha).
- `bin/rails test test/models/account_test.rb` → 57/169/0/0/0 (sanity: suite machinery healthy in-container).
- `bin/rubocop app/models/monarch/importer.rb test/models/monarch/importer_test.rb` → clean.
- ~7 known baseline-env failures (langfuse, simplefin ×3, hostings ×2, PG advisory-lock) were not rerun wholesale here; none of the touched code is in their path.

## Residual items — need Tayden's hands

1. **Plaid keys** — create at <https://dashboard.plaid.com/developers/keys>,
   set `PLAID_CLIENT_ID` / `PLAID_SECRET` / `PLAID_ENV=sandbox` in
   `deploy/mac/.env`, rerun `bin/rails plaid:sandbox_smoke`.
2. **Tailscale on the Mac** — the remote-access/launchd parts of the kit are
   inherently Mac-only; rehearse on the real machine.
3. **His real Monarch archive** — drop it in `deploy/mac/data/archive/` and run
   `monarch:import[/archive]` on the Mac; expect the same reconciliation
   guarantees now covered by the anchor fix.
4. *Optional:* `IMPORT_AUTO_FLAG_NEEDS_REVIEW=1` if he wants every imported row
   queued for review.

## Known gaps / notes

- Coinbase shows `cash_balance = 3200` (all-cash): imported holdings are
  point-in-time rows with no forward-fill, so non-cash value is invisible on the
  anchor date — the same semantics that pin the brokerage to `cash = total`.
  Acceptable; could be refined later by materializing an open-market-price for
  imported securities.
- `monarch:dedup` prints the review URL only when pairs exist (sensible, but a
  first-time reader may miss it — noted, not changed).
- `VALIDATION.json` in the fixture claims 11 accounts; `accounts.json` actually
  has 12 — the report/VALIDATION text is stale (worth a doc-only cleanup in a
  follow-up).
