# Monarch import runbook

How to load a Monarch Money export archive into this Sure instance, verify the
result, and roll it back if needed. Everything below assumes the Docker dev
stack in `.devcontainer/docker-compose.yml` — the same stack described in
`docs/llm-guides/development.md`.

## 0. Prerequisites

1. Docker stack running: `docker compose -f .devcontainer/docker-compose.yml up -d app`
   (first run builds the image; then `docker compose -f .devcontainer/docker-compose.yml exec app bin/setup` once).
2. A family already exists in Sure (sign up once in the UI, or seed).
   `monarch:import` imports into `Family.first` unless you pass `FAMILY_ID=<uuid>`.
3. The Monarch export archive extracted on your Mac. Layout must match
   `docs/monarch-import/SCHEMA.md` — an `import/` directory of `*.json`
   collection files plus `monarch.sqlite` and `VALIDATION.json`.

   The importer reads **`import/*.json` only**. `monarch.sqlite` is ignored
   (it duplicates the same records in SQLite form; see SCHEMA.md).

## 1. Make the archive visible inside the container

The `app` service bind-mounts the repo root at `/workspace`. Either:

- move/copy the extracted archive into the repo directory, e.g.
  `~/sure-monarch/monarch-archive/import/*.json` — then it is at
  `/workspace/monarch-archive` inside the container; or
- add a one-off volume: `docker compose -f .devcontainer/docker-compose.yml run --rm -v /path/to/monarch-archive:/archive app bash`
  (then the archive is at `/archive`).

`monarch-archive/` should stay out of git — the archive is real financial
data; never commit it.

## 2. Dry run first

```sh
docker compose -f .devcontainer/docker-compose.yml exec app \
  bin/rails "monarch:import[/workspace/monarch-archive,dry_run]"
```

(equivalently `DRY_RUN=1 bin/rails "monarch:import[/workspace/monarch-archive]"`)

Dry run executes the full import inside a transaction and rolls everything
back, then prints the reconciliation report: per collection — archive count,
created, updated, skipped (with reasons), errors — plus per-account
transaction totals comparing the archive's sums against what Sure would hold
(Sure's sign convention is inverted from Monarch's, so `archive` and
`imported` should be opposite signs with diff `0.0`). A `monarch_imports`
audit row with `dry_run: true` and the report JSON is kept; nothing else is
written.

## 3. Real import

```sh
docker compose -f .devcontainer/docker-compose.yml exec app \
  bin/rails "monarch:import[/workspace/monarch-archive]"
```

The same report prints at the end. The run is one DB transaction: any
unexpected failure aborts the whole import.

## 4. What to check afterward

1. **Report deltas** — every collection's `created` + `updated` + `skipped`
   should equal its archive count; the `skipped` reasons list explains each
   remainder (`future_month`, `unsupported_scope:*`, `reference_only`,
   `derived_or_not_applicable`, `date_anchored`, `no_target_amount`,
   `unknown_account`, `no_mappable_criteria`, `unsupported_frequency:*`).
   Per-account `diff` must be `0.0` everywhere.
2. **Spot-check in the UI** (http://localhost:3000):
   - accounts sidebar: balances match Monarch's `currentBalance`;
     hidden/deactivated accounts appear disabled and excluded from reports;
   - transactions: signs (expense positive), pending badge on `pending`
     rows, categories/merchants/tags applied;
   - investment accounts: holdings present with Monarch quantities and cost
     basis;
   - budgets: current and past months populated;
   - rules (`Settings → Rules`): Monarch rules present in original order
     (order is encoded in the rule name, e.g. `Monarch rule 3: ...` — Sure
     has no order field).
3. **Re-run safety** — run the same command again; the second report should
   show `created` = 0 and `updated` = the counts. Idempotency is keyed on
   `monarch_source_mappings` (family, collection, monarch_id).

## 5. Duplicate review (cross-source dedup)

After the real import finishes it prints a duplicate-candidate count. The
Plaid feed will re-deliver the last ~730 days of the same transactions, and
re-running `monarch:import` on a fresher export can double rows the feed
already delivered — `Dedup::Scanner` finds those pairs across sources and
accounts (`source=monarch` vs `source=plaid` for the same charge).

What it flags: pairs where the two rows come from different provenance
(`monarch` vs `plaid` vs `coinbase` vs …), or where at least one row has no
provenance at all (manual or CSV entries). What it does NOT flag: two rows
from the same store's own feed — when both entries carry the store's
`external_id` and the same `source`, they are two real transactions by
definition (daily savings transfers, repeated identical card charges), not
duplicates.

```sh
docker compose -f .devcontainer/docker-compose.yml exec app \
  bin/rails monarch:dedup
```

Prints candidate counts per account and confidence. Optional env vars:
`ACCOUNT_ID` (one account only), `DATE_WINDOW=5` (default ±3 days),
`LIMIT=500` (default 200), `INCLUDE_DISMISSED=1`, `SAME_SOURCE=1`
(re-enable same-store pairs — useful only for a CSV-double-upload cleanup,
not for imported/provider rows).

Review and merge in the UI: start the app (`bin/dev`), sign in, open
**http://localhost:3000/dedup/candidates**.

- Candidates are grouped by the surviving account and scored
  high/medium/low (name similarity, date gap, same/cross account,
  same/different source). The **Include same-source** filter toggle
  re-enables same-store pairs (same as `SAME_SOURCE=1`).
- **Merge** keeps the provider-backed row (plaid/coinbase/… over
  `source=monarch`, and pending rows always lose), absorbs the loser's
  category/merchant/notes/tags where the winner lacks them, clears
  `needs_review`, and records the merge in
  `transactions.extra["manual_merge"]` — the same marker provider syncs
  and `monarch:import` read so the removed row is never re-created
  (skipped as `merged_duplicate`).
- **Not a duplicate** persists a `Dedup::Dismissal` keyed on the pair's
  stable `source:external_id`s — the pair never resurfaces, even across
  re-imports that recreate the rows.

## 6. Reverting

```sh
docker compose -f .devcontainer/docker-compose.yml exec app \
  bin/rails monarch:revert
```

`Monarch::Reverter` deletes every record referenced by
`monarch_source_mappings` in FK-safe order (children before parents), the
mappings themselves, and the `monarch_imports` rows. Records you created or
edited by hand are untouched — but edits made on top of an imported record
go away with that record. The task prints per-collection delete counts.

Note: `monarch:revert` is mapping-driven, not the `Import` STI
`revert_import` flow — a Monarch import is intentionally not an `Import`
record.

## 6. Known gaps / decisions

- **`import/*.json` only** — `monarch.sqlite` is not read. If your archive's
  `import/` directory is incomplete, fix the export; don't point the task at
  the sqlite file.
- **`needsReview` / `reviewStatus`** are preserved on the transaction's
  `extra.monarch` blob (`pending`, `needs_review`, `review_status`,
  `data_provider_description`, `is_manual`, `hidden_by_account`). There is no
  Sure UI filter for them.
- **`credit_scores`, `settings_documents`** are stored on the `monarch_imports`
  row's `reference_documents` JSON — inspect with
  `bin/rails runner 'pp MonarchImport.last.reference_documents'`.
- **Derived series** (`net_worth_daily`, `portfolio_performance`,
  `transaction_activity`, `aggregate_holdings`, `tax_lots`, `equity_grants`,
  `attachments`, `provenance`) are never imported — they can be regenerated.
- **Recurring streams**: `daily`/unknown frequencies are skipped
  (`unsupported_frequency:*`); `semimonthly` becomes two monthly
  `RecurrenceRule`s; everything else maps to `RecurringTransaction` with
  `dedup_scope "monarch:<id>"`.
- **Budgets**: Monarch's future-planning rows past the current month are
  skipped; `group`-scoped budget rows are skipped (Sure budgets are
  per-category).
- **Rule order**: Monarch's `order` is imported into `rules.position` (dense
  per-family ordering via `Rule.reorder!`, first-match-wins application) and
  echoed in the generated rule name for readability.
- **Holdings** are imported as provider-authored snapshots. Monarch's archive
  has no trade ledger, so Sure's trade-derived holdings materialization is
  intentionally skipped for these rows (the importer passes the imported
  `security_ids` to `Balance::Materializer`, which suppresses the forward
  purge that would otherwise delete non-provider holdings). Cash positions
  (`type: "cash"`) inside investment accounts import correctly: they become
  `kind: "cash"` security holdings — shown as the "cash" slice in allocation —
  and fold into `cash_balance` rather than counting as invested value.
- **UI import** (zip upload via the `Import` STI) is not implemented — rake
  only. See the PR "Out of scope" notes.

## 7. Known archive quirks

Found in the first dry run against a real Monarch archive; all handled by the
importer today:

- **Multiple cash positions per account** — an account can export several
  `security.type == "cash"` holdings (money-market sweep funds like FDRXX/SPAXX,
  stablecoins like USDC-USD, the raw `CUR:USD` line). They are summed into one
  cash holding (`external_id: "cash:<monarch account id>"`, qty = amount = the
  summed value, price 1, dated at the archive's as-of date); every
  contributing Monarch holding id still maps to it.
- **Holdings carry no reliable timestamp** — most real `holdings` records
  have a null `closingPriceUpdatedAt` (a security-level field, usually
  unchanged on export day). Dating them at import day placed them a month
  after the archive's last valuation, which doubled investment balances
  (Sure carried the valuation forward as cash and added the holdings on
  top). Holdings now date at the archive's as-of date — the export date
  from `VALIDATION.json`'s `generated_at`, else the newest balance_history
  date, else today — and a non-null `closingPriceUpdatedAt` is kept only
  when it is not past as-of. The anchor valuation for accounts without
  balance_history dates at as-of for the same reason.
- **Deactivated accounts stop syncing before they close** — their
  balance_history typically ends days before `deactivatedAt`, so the
  imported balance would sit at the stale pre-closure amount while Monarch
  shows the closing balance (usually 0) and hides the account. The importer
  writes one closing valuation at `deactivatedAt` with the account's
  closing balance (`displayBalance`/`currentBalance`, 0 if null) so the
  balance series ends where the account actually closed, alongside the
  disabled/hidden flags `import_accounts` already sets.
- **Rules with no mappable criteria** are skipped as
  `no_mappable_criteria` — e.g. criteria on fields Sure does not carry. They
  leave no `rules` row and do not break position reordering of the others.
- **Operator spellings** — real archives use `eq` / `neq` / `ne` / `not_eq`
  for text and `eq` / `neq` / `ne` / `gt` / `gte` / `lt` / `lte` for amounts,
  alongside the snake_case/camelCase spellings already mapped. Unknown
  operators skip that criterion (and the rule if it has none left).
- **Securities typed `other` / `option` / `derivative`** — e.g. 401(k)
  target-date funds with no ticker — import with a nil `asset_sub_class` (the
  only valid value for these types) and a synthetic `MONARCH-<security id>`
  ticker.
