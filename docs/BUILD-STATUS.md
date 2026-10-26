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
| W1-A Monarch archive importer (rake + source-ID mapping + reconciliation + revert + RUNBOOK) | [1ee31583](https://app.devin.ai/sessions/1ee315839eec4395a30565cf13ca214c) | [#6](https://github.com/tayden-b/sure-monarch/pull/6) | **merged** (by Tayden at 19:39Z while `test_system` was still running — all other checks green; branch CI verified after) | 18738d7e |
| W1-B Plaid self-host (env URLs, 730-day history, Sandbox smoke, docs/setup/PLAID.md) | [58db1784](https://app.devin.ai/sessions/58db178441a3439e853eb361e6259c0a) | [#4](https://github.com/tayden-b/sure-monarch/pull/4) | **merged** | d0166aa2 |
| W1-C Parity gap audit → docs/PARITY-AUDIT.md | [23264c42](https://app.devin.ai/sessions/23264c421ec346d98b32579a4b97eb38) | [#2](https://github.com/tayden-b/sure-monarch/pull/2) | **merged** | 73464ca1 |
| W1-D Mac deploy kit (deploy/mac, docs/setup/MAC.md) | [df23b31c](https://app.devin.ai/sessions/df23b31c19a74337b4ceb216386d2b67) | [#3](https://github.com/tayden-b/sure-monarch/pull/3) | **merged** | 59e100f1 |
| W1-E Encryption tests + fork CI green | [4b3f0238](https://app.devin.ai/sessions/4b3f023839cb465b9ae396cee5e4d118) | [#5](https://github.com/tayden-b/sure-monarch/pull/5) | **merged** | 0e07cb84 |

## Wave 2 — parity surfaces

Dispatched per `docs/PARITY-AUDIT.md` §3 (T-numbering is the audit's).
Batch 1 = 6 parallel workers on non-overlapping file sets; batch 2
(T3 dedup, T4 rule ordering, T6 merchant report, T7 flex budget) follows
once batch-1 dependencies land (T3 needs needs-review + importer
provenance; T4 after T2's rule-executor edit; T6/T7 after T1). All ten
tasks are now dispatched — **all 10 merged**; follow-up worker W2-F in flight, integration gate next.

| Task | Session | PR | Status | Merged SHA |
|---|---|---|---|---|
| T1 Category classification + groups (swe-2-max) | [a9625182](https://app.devin.ai/sessions/a962518265df4a33a0520b287724f121) | [#12](https://github.com/tayden-b/sure-monarch/pull/12) | **merged** | 9caadf6c |
| T9 Accounts flags + type-first grouping (swe-2-max) | [16248e1e](https://app.devin.ai/sessions/16248e1e62994260ad45b6d12970a66f) | [#9](https://github.com/tayden-b/sure-monarch/pull/9) | **merged** (1 correction round: system tests→`view=connections`) | fe8cdd0f |
| T2 Needs-review queue (swe-2-max) | [0dd05265](https://app.devin.ai/sessions/0dd052659b2f466185238c125c67113d) | [#10](https://github.com/tayden-b/sure-monarch/pull/10) | **merged** | 1a15d68f |
| T5 Aggregate holdings + allocation (swe-2-max) | [f70e472b](https://app.devin.ai/sessions/f70e472bb5c448a0b0e9cbbdb6d6ada0) | [#7](https://github.com/tayden-b/sure-monarch/pull/7) | **merged** | 64cab29f |
| T8 Mobile transactions UX (swe-2-max) | [182aa65f](https://app.devin.ai/sessions/182aa65ff25441e5b9fe7a2b13bc0636) | [#11](https://github.com/tayden-b/sure-monarch/pull/11) | **merged** | fcb8d3ec |
| T10 Recurring polish (swe-2-high) | [0eb00f24](https://app.devin.ai/sessions/0eb00f24c7eb42639ec273b6daa0b468) | [#8](https://github.com/tayden-b/sure-monarch/pull/8) | **merged** | 8c9df482 |
| T3 Cross-source dedup (swe-2-max) | [db5dae27](https://app.devin.ai/sessions/db5dae271fb34caaa7994889e5f6d041) | [#14](https://github.com/tayden-b/sure-monarch/pull/14) | **merged** | f1cf5572 |
| T4 Rule ordering (swe-2-max) | [aa20bfb5](https://app.devin.ai/sessions/aa20bfb5b8c7409c91e1f1d85e69da8c) | [#13](https://github.com/tayden-b/sure-monarch/pull/13) | **merged** | 88f3be95 |
| T6 Merchant spend report (swe-2-max) | [b33e15dc](https://app.devin.ai/sessions/b33e15dc395b47e28034fbb30487fe78) | [#16](https://github.com/tayden-b/sure-monarch/pull/16) | **merged** | b0970d8c |
| T7 Flex/discretionary budget (swe-2-max) | [7110bf7e](https://app.devin.ai/sessions/7110bf7e4a4c41b09d578caca4b14660) | [#15](https://github.com/tayden-b/sure-monarch/pull/15) | **merged** (migration renumbered by orchestrator — 210000 collided with dedup) | 59aa799e |

## Integration gate

**COMPLETE** — [#18](https://github.com/tayden-b/sure-monarch/pull/18) merged (`6361dd98`). One worker rehearsed the full setup on a clean VM —
deploy kit, synthetic archive import + reconciliation counts, every parity
surface at desktop and mobile widths, Plaid Sandbox smoke, backup/restore.

## Open issues / follow-ups reported by workers

- Plaid Sandbox smoke task (`plaid:sandbox_smoke`) could not be exercised against
  real Plaid Sandbox in the cloud — no Plaid account exists yet. Runnable by
  Tayden after he creates dashboard keys (docs/setup/PLAID.md step 2).
- Webhooks need Funnel permanently on for real-time pushes; manual Sync is the
  documented alternative if he doesn't want the app public 24/7.
- Importer defers remaining: group-scoped/future budget rows, daily
  recurring frequencies — accepted limitations (documented in RUNBOOK).
  **Fixed by W2-F** (#17): rule positions now imported via `Rule.reorder!`
  in Monarch order; cash-kind holdings double-count in `Balance::SyncCache`
  fixed (fixture brokerage was 25500 vs 25000 — now reconciles).
- T10 follow-up: `Demo::Generator#create_transfer!` leg kinds — **fixed by W2-F** (#17): outflow = `Transfer.kind_for_account(destination)`, inflow = `funds_movement`.
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

Build complete. Tayden runs `docs/HANDOFF.md` on his Mac (≈35–50 min active).
Remaining deferrals are documented in "Open issues" above: Plaid keys,
Tailscale on the real Mac, his real archive, and accepted importer defers.
