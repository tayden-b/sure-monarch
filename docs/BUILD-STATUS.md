# Monarch Replacement — Build Status

Single-user self-hosted Monarch Money replacement on this Sure fork.
Base branch: `monarch-baseline`. Orchestrated by Devin; workers run under the
"sure-monarch worker contract" playbook. This file is the source of truth for
where the build stands — updated by the orchestrator after every merge.

## Decisions made

| Decision | Call | Why |
|---|---|---|
| Hosting | ~~Tayden's Mac~~ → **public VPS** (OVH VPS-1, Ubuntu 26.04) + Caddy auto-HTTPS — changed 2026-10-26 | His Mac is a corporate laptop: Tailscale and personal financial data aren't allowed on it. Plain HTTPS on a real hostname (`money.tayden.dev`) replaces Serve/Funnel. |
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

## Wave 3 — deploy retarget

| Task | Session | PR | Status | Merged SHA |
|---|---|---|---|---|
| W3-A VPS deploy kit (`deploy/vps/`, docs/setup/VPS.md, HANDOFF.md rewrite, rehearsal) | [26748c93](https://app.devin.ai/sessions/26748c93dfb6429196e1bea18b6a4614) | [#20](https://github.com/tayden-b/sure-monarch/pull/20) | **merged** | `06232c58` |

## Integration gate

**COMPLETE** — [#18](https://github.com/tayden-b/sure-monarch/pull/18) merged (`6361dd98`). One worker rehearsed the full setup on a clean VM —
deploy kit, synthetic archive import + reconciliation counts, every parity
surface at desktop and mobile widths, Plaid Sandbox smoke, backup/restore.

## Wave 4 — provider linking

| Task | Session | PR | Status | Merged SHA |
|---|---|---|---|---|
| W4-A Attach linked accounts to imported accounts + auto-merge exact overlaps (auto-attach on first sync by mask/payload/institution; manual "Attach to existing" for sync-created shells; `Dedup::AutoMerger` post-sync; `PLAID_HISTORY_DAYS` doc'd in HANDOFF §7) | this session | `work/attach-provider-to-existing` | **open** | — |

## Open issues / follow-ups reported by workers

- Plaid Sandbox smoke task (`plaid:sandbox_smoke`) could not be exercised against
  real Plaid Sandbox in the cloud — no Plaid account exists yet. Runnable by
  Tayden after he creates dashboard keys (docs/setup/PLAID.md step 2).
- Webhooks now ride the public `money.tayden.dev` hostname (Caddy), so no
  Funnel is needed — superseded by the VPS retarget.
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
- First real-archive dry run (on the VPS) surfaced 4 importer defects —
  multi-cash holdings, rule reorder after a skipped rule, real operator
  spellings (eq/lt/gt…), unmapped security types — **fixed + merged** in
  [#21](https://github.com/tayden-b/sure-monarch/pull/21) (`e2ba4d25`);
  quirks documented in RUNBOOK §7.
- [#19](https://github.com/tayden-b/sure-monarch/pull/19) merged (`931b541a`):
  flex edit now turbo-refreshes the plan headroom/donut region (T7 leftover).
- [#23](https://github.com/tayden-b/sure-monarch/pull/23) merged (`534ec7c5`):
  imported holdings dated at the archive's as-of/validated_at (not import day)
  so net-worth history isn't backdated flat; deactivated Monarch accounts
  import as closed.
- [#24](https://github.com/tayden-b/sure-monarch/pull/24) merged (`054a556b`):
  `bin/upgrade` normalizes data/archive perms as root before dropping to
  `sure` — fixes the live-box `permission denied` on the build context.
- [#25](https://github.com/tayden-b/sure-monarch/pull/25) merged (`f1408969`):
  dedup scanner no longer pairs two rows from the same provenance
  (source + external_id both present, same source) — the 200 same-store
  Monarch pairs on the live box were false positives. `SAME_SOURCE=1` /
  `/dedup/candidates` "Include same-source" toggle preserves the
  CSV-double-upload cleanup path. Also bumps `test_unit` CI timeout 10→20m
  (runner setup growth was cancelling the job mid-suite).
- [#26](https://github.com/tayden-b/sure-monarch/pull/26) merged (`f725fdca`) —
  the gating PR before linking real banks. Linking an institution now attaches
  to the imported Monarch twin instead of duplicating it: auto-attach on first
  sync (mask-in-name → payload mask → unique plaidInstitutionId; unique
  institution-name for Coinbase/Kraken; any ambiguity → create new), imported
  names locked against provider rename, "Link provider" modal + `providers:attach`
  move a feed off a provider-created shell (`AccountProvider::Reattach` — refuses
  non-shell sources, other-family targets, occupied targets, and cross-class
  attaches added in review), `PLAID_HISTORY_DAYS` honored (set ≈75 before first
  link), and `Dedup::AutoMerger` post-sync merges exact cross-source overlaps
  (same account, same amount+currency, ≤1d, name ≥0.8, monarch losers only,
  `families.auto_merge_duplicates` default on).
- **Live verified**: re-import on the VPS with #23 — all 25 real accounts
  match Monarch to the cent; net worth $365,766 (RSU excluded as in Monarch);
  Plaid sandbox smoke passed (redirect-URI dashboard step pending Tayden).
- VPS kit OVH fixes **merged** in [#22](https://github.com/tayden-b/sure-monarch/pull/22)
  (`75e9eca6`): sshd drop-in renamed 00-* (beats cloud-init's 50-*, verified via
  `sshd -T`) + lockout guard + root key-mirror extended to sudo user, archive
  perms → container uid 1000 (`bin/fix-archive-perms`), `.dockerignore` keeps
  data/backups/.env out of the build context.

## What Tayden must do by hand (running list)

1. Create the Plaid account/app and pull Sandbox keys — docs/setup/PLAID.md §1–2.
2. Request Plaid Trial (Limited Production) access — same doc §5.
3. Create Coinbase CDP + Kraken API keys (read-only perms in same doc §7).
4. Create the OVH VPS-1 + DNS A record, run `deploy/vps/bin/setup-vps` — docs/setup/VPS.md.
5. `scp` his real Monarch archive to the VPS and run the import — docs/monarch-import/RUNBOOK.md.
6. Link each institution (one Plaid Item each — 10 max on Trial; Coinbase/Kraken via Settings → Providers).

A consolidated ordered checklist lands in docs/HANDOFF.md at the end of the build.

## What's next

Build complete and **live**: https://money.tayden.dev is up, account created,
onboarding closed, Plaid sandbox keys set, real-archive import run (4
importer defects found + fixed, #21). Remaining: production Plaid keys + institution links per docs/HANDOFF.md §6–7,
then re-run `monarch:import` on the real archive with the #21 fixes.
