# Monarch Replacement — Build Status

Single-user self-hosted Monarch Money replacement on this Sure fork.
Base branch: `monarch-baseline`. Orchestrated by Devin; workers run under the
"sure-monarch worker contract" playbook. This file is the source of truth for
where the build stands — updated by the orchestrator after every merge.

## Decisions made

| Decision | Call | Why |
|---|---|---|
| Hosting | Tayden's Mac (Apple Silicon), Docker Desktop + Tailscale | Serve for tailnet HTTPS; Funnel only for Plaid redirect/webhook paths |
| Connectivity | Plaid free Trial (10 Items) for banks/brokerages; Coinbase + Kraken via Sure's direct providers | No new providers built — uncovered institutions (Fidelity NetBenefits, pension, Morgan Stanley/EquatePlus, Gemini) become manual/CSV accounts |
| Data | Tayden's real Monarch archive never leaves his Mac | Workers build/test against synthetic fixtures matching `docs/monarch-import/SCHEMA.md` |
| Import surface | `bin/rails monarch:import[...]` rake task, not the `Import` STI upload UI | Archive is a directory of JSON, not a single CSV; UI upload deferred as nice-to-have |
| History depth | `PLAID_HISTORY_DAYS` default 730 (Plaid's cap) | Self-host env previously backfilled only 90 days |
| Orchestrator | This build is orchestrated by session devin-3f8c13dcd2aa499980e3084e8f8df432 | An earlier API-created orchestrator (610e4b09…) was stood down after merging PRs #2/#3/#5 |

## Wave 1 — foundations

| Task | Session | PR | Status | Merged SHA |
|---|---|---|---|---|
| W1-A Monarch archive importer (rake + source-ID mapping + reconciliation + revert + RUNBOOK) | [1ee31583](https://app.devin.ai/sessions/1ee315839eec4395a30565cf13ca214c) | [#6](https://github.com/tayden-b/sure-monarch/pull/6) | open — under review, CI pending | — |
| W1-B Plaid self-host (env URLs, 730-day history, Sandbox smoke, docs/setup/PLAID.md) | [58db1784](https://app.devin.ai/sessions/58db178441a3439e853eb361e6259c0a) | [#4](https://github.com/tayden-b/sure-monarch/pull/4) | **merged** | d0166aa2 |
| W1-C Parity gap audit → docs/PARITY-AUDIT.md | [23264c42](https://app.devin.ai/sessions/23264c421ec346d98b32579a4b97eb38) | [#2](https://github.com/tayden-b/sure-monarch/pull/2) | **merged** | 73464ca1 |
| W1-D Mac deploy kit (deploy/mac, docs/setup/MAC.md) | [df23b31c](https://app.devin.ai/sessions/df23b31c19a74337b4ceb216386d2b67) | [#3](https://github.com/tayden-b/sure-monarch/pull/3) | **merged** | 59e100f1 |
| W1-E Encryption tests + fork CI green | [4b3f0238](https://app.devin.ai/sessions/4b3f023839cb465b9ae396cee5e4d118) | [#5](https://github.com/tayden-b/sure-monarch/pull/5) | **merged** | 0e07cb84 |

## Wave 2 — parity surfaces

Not yet dispatched. Dispatch follows `docs/PARITY-AUDIT.md` (merged via #2),
priority order: accounts/net-worth overview → unified transactions feed + rules
→ mobile-browser UX → investments/holdings → recurring → cash-flow reports &
budgets → data hygiene (import↔Plaid dedup, import revert UX).

| Task | Session | PR | Status | Merged SHA |
|---|---|---|---|---|
| — | — | — | pending dispatch | — |

## Integration gate

Not started. After Wave 2: one worker rehearses the full setup on a clean VM —
deploy kit, synthetic archive import + reconciliation counts, every parity
surface at desktop and mobile widths, Plaid Sandbox smoke, backup/restore.

## Open issues / follow-ups reported by workers

- Plaid Sandbox smoke task (`plaid:sandbox_smoke`) could not be exercised against
  real Plaid Sandbox in the cloud — no Plaid account exists yet. Runnable by
  Tayden after he creates dashboard keys (docs/setup/PLAID.md step 2).
- Webhooks need Funnel permanently on for real-time pushes; manual Sync is the
  documented alternative if he doesn't want the app public 24/7.
- Importer defers: `needsReview`/`reviewStatus` UI filtering (stored in
  `extra.monarch` only), rule ordering (in names only), group-scoped/future
  budget rows, daily recurring frequencies, cash-position splitting inside
  investment accounts.
- Gemini has no provider — manual/CSV account path documented.
- Pre-existing test-env failures on baseline (eval/langfuse, simplefin ×3,
  hostings ×2, PG advisory-lock flake) reproduce without any changes — not
  caused by this build; workers must keep reporting them as baseline failures.

## What Tayden must do by hand (running list)

1. Create the Plaid account/app and pull Sandbox keys — docs/setup/PLAID.md §1–2.
2. Request Plaid Trial (Limited Production) access — same doc §5.
3. Create Coinbase CDP + Kraken API keys (read-only perms in same doc §7).
4. Run the Mac deploy kit + Tailscale expose — docs/setup/MAC.md.
5. Drop his real Monarch archive on the Mac and run the import — docs/monarch-import/RUNBOOK.md.
6. Link each institution (one Plaid Item each — 10 max on Trial).

A consolidated ordered checklist lands in docs/HANDOFF.md at the end of the build.

## What's next

1. Merge PR #6 (importer) once CI is green.
2. Dispatch Wave 2 workers per docs/PARITY-AUDIT.md.
3. Integration-gate rehearsal worker.
4. docs/HANDOFF.md + final report to Tayden.
