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

## 5. Reverting

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
- **Rule order**: preserved only via the generated rule name; Sure's rules
  engine has no order column.
- **Holdings** are imported as provider-authored snapshots. Monarch's archive
  has no trade ledger, so Sure's trade-derived holdings materialization is
  intentionally skipped for these rows (the importer passes the imported
  `security_ids` to `Balance::Materializer`, which suppresses the forward
  purge that would otherwise delete non-provider holdings).
- **UI import** (zip upload via the `Import` STI) is not implemented — rake
  only. See the PR "Out of scope" notes.
