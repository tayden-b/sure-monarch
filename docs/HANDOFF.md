# Handoff — run Sure (Monarch replacement) on your Mac

One ordered checklist. Estimated **35–50 min of active time** plus one 10–20 min
docker build you can walk away from. Every command is copy-pasteable; the
rehearsal report (`docs/REHEARSAL.md`) proves each step works on a clean machine.

Legend: ⌨️ = run in Terminal on the Mac · 🖱️ = click in a browser · 📝 = edit a file.

---

## 0. Prerequisites (once)

- ⌨️ Install + open **Docker Desktop for Mac** (whale icon steady in the menu bar):
  https://docs.docker.com/desktop/install/mac-install/
  Then: Docker Desktop → Settings → General → **"Start Docker Desktop when you sign in"** ✅
- ⌨️ Install **Tailscale** + sign in: https://tailscale.com/download/mac
  (also install Tailscale on your phone, same tailnet — that's your remote access)
- 🖱️ Get your **Monarch export** from Monarch → Settings → Export, extract the zip.
  You should have a folder containing `import/*.json` + `monarch.sqlite`.
- 🖱️ Create a free **Plaid** account: https://dashboard.plaid.com/signup
  (verify email; skip production-access prompts for now — you do that in step 6)

## 1. Get the code + run the app (~20 min, mostly the build)

```bash
# ⌨️ wherever you keep repos
git clone https://github.com/tayden-b/sure-monarch.git
cd sure-monarch
git checkout monarch-baseline
cd deploy/mac
./bin/setup-mac
```

- The script writes `.env` (auto-generates every secret it can) and prompts for a
  few optional keys — **press Enter to skip everything** for now, or paste
  `PLAID_CLIENT_ID`/`PLAID_SECRET` if you already made a Plaid app.
- First `docker compose build` takes 10–20 min — walk away.
- Done when it prints `Done` and your URLs.

🖱️ Open **http://localhost:3000** → create your account → finish the 3-step
onboarding wizard. (First user = admin.)

## 2. Remote HTTPS via Tailscale (phone access)

```bash
# ⌨️ still in deploy/mac
./bin/tailscale-expose
docker compose up -d
```

- This runs `tailscale serve` and writes `APP_DOMAIN` + `RAILS_ASSUME_SSL` into `.env`.
- 🖱️ Verify on your phone: `https://<your-mac>.<tailnet>.ts.net` (exact name:
  `tailscale status`). Log in — it must work before Plaid step 6.

## 3. Lock the door

📝 In `deploy/mac/.env` change `ONBOARDING_STATE=open` → `ONBOARDING_STATE=closed`
(so nobody else can sign up), then:

```bash
# ⌨️
docker compose up -d
```

## 4. Import your Monarch history (~5–15 min depending on archive size)

```bash
# ⌨️ put the extracted export where the containers see it
cp -R /path/to/monarch-export/ deploy/mac/data/archive/
# the folder must end up as deploy/mac/data/archive/import/*.json

# dry run first — writes nothing, prints the reconciliation report
docker compose exec -T web bin/rails "monarch:import[/archive,dry_run]"

# real run
docker compose exec -T web bin/rails "monarch:import[/archive]"
```

Verify in the printed report: every collection's `created`+`updated`+`skipped`
sums to its archive row count; `skipped` reasons are the documented ones
(future-month budgets, group-scoped budgets, derived/reference collections).
Then:

```bash
# cross-source duplicate scan — prints counts + a review URL if it finds pairs
docker compose exec -T web bin/rails monarch:dedup
```

🖱️ Open **http://localhost:3000/accounts** — every account balance must equal
Monarch's (net worth = your Monarch total). If anything is off, check
`docker compose exec -T web bin/rails "monarch:revert"` exists to undo fully —
see `docs/monarch-import/RUNBOOK.md` §rollback.

## 5. Clear the review queues (~5 min)

- 🖱️ **http://localhost:3000/transactions** → "Needs review" chip: imported rows
  flagged `needsReview` in Monarch. Skim, unflag what looks right.
- 🖱️ **http://localhost:3000/dedup/candidates** → merge confirmed duplicates,
  dismiss false positives. (Worth re-running after each bank's first sync —
  Plaid's 730-day backfill will overlap your imported history.)

## 6. Plaid — sandbox first, then production Trial (~15 min)

```bash
# ⌨️ paste your Sandbox keys into deploy/mac/.env:
#   PLAID_CLIENT_ID / PLAID_SECRET / PLAID_ENV=sandbox   (dashboard → developers/keys)
docker compose up -d
docker compose exec -T web bin/rails plaid:sandbox_smoke
# must print: SUCCESS: Plaid Sandbox smoke test passed — if not, stop here.
```

Public paths for webhooks + OAuth redirect:

```bash
# ⌨️
./bin/tailscale-expose --funnel   # exposes ONLY /webhooks/plaid* and /accounts
docker compose up -d
```

- 🖱️ Plaid dashboard → **Team settings → API → Allowed redirect URIs**: add
  `https://<your-mac>.<tailnet>.ts.net/accounts` (https, no trailing slash).
- 🖱️ Dashboard → **Get production access** → choose **Trial** (free). When
  approved, switch `.env` to the **production** secret + `PLAID_ENV=production`,
  then `docker compose restart web worker`.

## 7. Link everything (~10 min)

🖱️ App → **Accounts → Link account** — one Plaid Item per institution (Trial
gives you 10; you're expected to use ~6):

| Link via | Institutions |
|---|---|
| Plaid OAuth | Chase, Amex, SoFi, Fidelity (personal brokerage/IRA/HSA), Robinhood |
| Plaid login (maybe) | Fidelity NetBenefits 401(k) — coverage varies; if it won't link → manual account |
| Coinbase provider | CDP API key at https://portal.cdp.coinbase.com/access/api — **View (read-only)** only |
| Kraken provider | Kraken → Settings → API — **Query Funds** + **Query Closed Orders & Trades** (Query Ledger recommended); all trade/withdraw perms OFF |
| Manual Investment accounts | Morgan Stanley/EquatePlus, pension — Plaid can't reach these |
| Manual CreditCard/CSV | Gemini card (Plaid's "Gemini" is the exchange only), Gemini exchange |

🖱️ After each Plaid link: watch the first sync land —
`docker compose logs -f worker`. Then re-run `monarch:dedup` and clear
`/dedup/candidates` again (this is where imported history meets live feed).

## 8. Safety net

```bash
# ⌨️
./bin/backup              # first snapshot now — backups/*.dump, keeps last 14
./bin/install-launchd     # compose autostart at login + nightly 03:15 backup
```

## 9. Daily driver check

- 🖱️ Dashboard net-worth chart, `/transactions` feed, `/budgets` flex card,
  `/reports` (incl. Spending by Merchant), `/recurring_transactions`,
  `/holdings` — all should be populated.

## If something breaks

| Symptom | Fix |
|---|---|
| `./bin/setup-mac` dies early | `docker info` must work first — open Docker Desktop, wait, re-run. Script is idempotent. |
| Build fails pulling images | Docker Hub rate limit — wait a few min, `docker compose build` again. |
| `/up` never healthy | `docker compose logs web` — usually a missing `.env` value; compare against `.env.example`. |
| `plaid:sandbox_smoke` skips | It needs `PLAID_CLIENT_ID`/`PLAID_SECRET`/`PLAID_ENV=sandbox` set + `docker compose up -d`. |
| Plaid OAuth loop/error | Redirect URI must be exactly `https://<mac>.<tailnet>.ts.net/accounts` in the dashboard AND match `APP_DOMAIN`/`.env`; Funnel on (`tailscale funnel status`). |
| Institution won't link | Check the table in step 7 — some are manual by design. Nothing is lost: manual account or CSV. |
| Duplicates after first bank sync | Expected — `docker compose exec -T web bin/rails monarch:dedup` → `/dedup/candidates`. Provider rows win merges (that's correct — they keep syncing). |
| Re-run import | `docker compose exec -T web bin/rails "monarch:revert"` first (full delete of imported records), then re-import. |
| Want factory reset | `docker compose down -v` (deletes DB) → `./bin/setup-mac`. `./bin/backup` FIRST. |
| Docs needed mid-flow | `docs/setup/MAC.md` (kit), `docs/setup/PLAID.md` (Plaid detail), `docs/monarch-import/RUNBOOK.md` (import detail), `docs/REHEARSAL.md` (what was proven). |
