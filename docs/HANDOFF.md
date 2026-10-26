# Handoff — run Sure (Monarch replacement) on your VPS

One ordered checklist. Estimated **45–60 min of active time** plus one 10–20 min
docker build you can walk away from. Every command is copy-pasteable; the
rehearsal report (`docs/REHEARSAL.md` §VPS) proves each step works on a clean machine.

Legend: ⌨️ = run in a terminal on YOUR laptop · 🖥️ = run on the VPS over SSH ·
🖱️ = click in a browser · 📝 = edit a file.

---

## 0. Prerequisites (once)

- 🖱️ Get your **Monarch export**: Monarch → Settings → Export, extract the zip.
  You should have a folder containing `import/*.json` + `monarch.sqlite`.
- 🖱️ Have your **Plaid** keys ready (you already have production Trial keys):
  https://dashboard.plaid.com/developers/keys — keep the page open.
- ⌨️ Make sure you have an **SSH key** on your laptop:
  `ls ~/.ssh/id_ed25519.pub || ssh-keygen -t ed25519` (press Enter through prompts).

## 1. Create the VPS (~10 min)

- 🖱️ OVHcloud → **Public Cloud → VPS → order a VPS-1** (2 vCPU / 4 GB / 40 GB NVMe):
  https://www.ovhcloud.com/en/vps/
  - Image: **Ubuntu 26.04 LTS** (64-bit, x86_64)
  - SSH key: paste your `~/.ssh/id_ed25519.pub` during checkout
  - No extras needed (no backup option — the kit backs up itself)
- When it's live, note the **public IPv4** (OVH email + dashboard).

## 2. Point the hostname at it (~5 min)

- 🖱️ In your DNS provider for `tayden.dev`, create **one A record**:
  `money.tayden.dev → <vps-public-ipv4>` (TTL 300).
- **No domain?** Use `<vps-ip>.sslip.io` (e.g. `51.210.42.17.sslip.io`) — it
  resolves for free. Caveat: Let's Encrypt rate-limits `sslip.io` hostnames
  frequently; cert issuance may fail or take retries. A real domain is strongly
  preferred — sslip.io is the documented fallback, not the recommendation.
- ⌨️ Verify from your laptop: `dig +short money.tayden.dev` → must return the VPS IP.
  Proceed only when it does (a minute or two, usually).

## 3. Install the app (~20 min, mostly a build)

```bash
# ⌨️ from your laptop
ssh root@<vps-public-ipv4>
```

```bash
# 🖥️ on the VPS
git clone https://github.com/tayden-b/sure-monarch.git /tmp/sure-setup
cd /tmp/sure-setup
git checkout monarch-baseline
sudo deploy/vps/bin/setup-vps
```

- The script installs + hardens everything (Docker, ufw, fail2ban, sshd,
  `sure` user, systemd units, nightly backup timer), generates every secret into
  `deploy/vps/.env`, and prompts **only** for:
  - `APP_DOMAIN` → answer: `money.tayden.dev`
  - `PLAID_CLIENT_ID` / `PLAID_SECRET` / `PLAID_ENV` → paste them now or press
    Enter through to skip (you can add them later — step 6).
- First `docker compose build` takes 10–20 min — walk away.
- Done when it prints `==> Done` and `Site: https://money.tayden.dev`.
- The repo now lives at `/opt/sure` (owned by the `sure` user); the kit dir is
  `/opt/sure/deploy/vps`. Remove the bootstrap clone: `rm -rf /tmp/sure-setup`.

## 4. First sign-in + lock the door (~5 min)

- 🖱️ Open **https://money.tayden.dev** → create your account → finish the
  3-step onboarding wizard. (First user = admin; Let's Encrypt cert is automatic.)
- 📝 Lock signup so nobody else can register:

```bash
# 🖥️ on the VPS (as root or `ssh sure@<ip>`)
cd /opt/sure/deploy/vps
sed -i 's/^ONBOARDING_STATE=.*/ONBOARDING_STATE=closed/' .env
docker compose up -d
```

- 🖱️ Turn on 2FA: app → **Settings → Security → Multi-factor authentication** —
  scan the TOTP QR into your authenticator app.

## 5. Import your Monarch history (~10–20 min)

```bash
# ⌨️ from your laptop — copy the export up (ends up mounted at /archive in the app)
scp -r /path/to/monarch-export/ sure@<vps-public-ipv4>:/opt/sure/deploy/vps/data/archive/
# the files must land as deploy/vps/data/archive/import/*.json
```

```bash
# 🖥️ on the VPS
cd /opt/sure/deploy/vps
# dry run first — writes nothing, prints the reconciliation report
docker compose exec -T web bin/rails "monarch:import[/archive,dry_run]"
# real run
docker compose exec -T web bin/rails "monarch:import[/archive]"
# cross-source duplicate scan — prints counts + a review URL if it finds pairs
docker compose exec -T web bin/rails monarch:dedup
```

Verify in the printed report: every collection's `created`+`updated`+`skipped`
sums to its archive row count; `skipped` reasons are the documented ones
(future-month budgets, group-scoped budgets, derived/reference collections).

🖱️ Open **https://money.tayden.dev/accounts** — every balance must equal
Monarch's (net worth = your Monarch total). If anything is off,
`docker compose exec -T web bin/rails "monarch:revert"` deletes every imported
record — see `docs/monarch-import/RUNBOOK.md` §rollback.

## 6. Plaid — production Trial (~10 min)

```bash
# 🖥️ on the VPS — set your production keys (edit .env, or this one-liner appends/replaces)
cd /opt/sure/deploy/vps
for kv in "PLAID_CLIENT_ID=<your id>" "PLAID_SECRET=<your production secret>" "PLAID_ENV=production"; do
  key="${kv%%=*}"; grep -q "^${key}=" .env && sed -i "s|^${key}=.*|${kv}|" .env || echo "$kv" >> .env
done
docker compose up -d
# optional sanity pass first: PLAID_ENV=sandbox + sandbox keys, then
#   docker compose exec -T web bin/rails plaid:sandbox_smoke
```

- 🖱️ Plaid dashboard → **Team settings → API → Allowed redirect URIs**: add
  `https://money.tayden.dev/accounts` (https, no trailing slash).
- `PLAID_REDIRECT_URI` and `PLAID_WEBHOOK_URL` were auto-derived from
  `APP_DOMAIN` in `.env` (`https://money.tayden.dev/accounts` and
  `.../webhooks/plaid`) — no manual edit needed unless you change the hostname.

## 7. Link everything (~15 min)

🖱️ App → **Accounts → New account → Link via provider** — one connection per
institution (Trial gives you 10 Plaid Items):

| Link via | Institutions |
|---|---|
| Plaid OAuth | Chase, Amex, SoFi, Fidelity (personal brokerage/IRA/HSA), Robinhood |
| Plaid login (maybe) | Fidelity NetBenefits 401(k) — coverage varies; if it won't link → manual account |
| Coinbase provider (Settings → Providers → Coinbase) | CDP API key at https://portal.cdp.coinbase.com/access/api — **View (read-only)** only |
| Kraken provider (Settings → Providers → Kraken) | Kraken → Settings → API — **Query Funds** + **Query Closed Orders & Trades**; all trade/withdraw perms OFF |
| Manual Investment accounts | Morgan Stanley/EquatePlus, pension — no provider reaches these |
| Manual CreditCard/CSV | Gemini card + exchange — Plaid's "Gemini" is the exchange only |

🖱️ After each link: watch the first sync land — `docker compose logs -f worker`.
Then re-run `monarch:dedup` and clear `/dedup/candidates` (imported history
meeting live feed is where duplicates appear; provider rows win merges — correct).

## 8. Safety net (~5 min)

```bash
# 🖥️ on the VPS
cd /opt/sure/deploy/vps
./bin/backup            # first snapshot now — backups/*.dump, keeps last 14
systemctl list-timers sure-backup.timer   # confirm nightly 03:15 timer is armed
```

```bash
# ⌨️ from your laptop — pull an off-box copy (any cron/weekday habit works too)
cd /path/to/sure-monarch/deploy/vps
./bin/pull-backup sure@<vps-public-ipv4>            # → ./backups-pulled/
```

## 9. Daily driver check

- 🖱️ Dashboard net-worth chart, `/transactions` feed, `/budgets` flex card,
  `/reports` (incl. Spending by Merchant), `/recurring_transactions`,
  `/holdings` — all should be populated.
- 🔁 Upgrades later: `ssh sure@<ip>` → `cd /opt/sure/deploy/vps` →
  `./bin/upgrade` (back up first, git pull, rebuild, restart, migrate).

## If something breaks

| Symptom | Fix |
|---|---|
| `setup-vps` dies early | It's idempotent — fix the cause, re-run it. apt lock errors mean `unattended-upgrades` is still running; wait a minute. |
| Cert not issued / self-signed warning | DNS A record must resolve to the VPS + ports 80/443 open. `docker compose logs caddy` shows ACME errors. sslip.io is often LE-rate-limited — use a real domain. |
| `ssh sure@<ip>` denied | Your laptop key must be in root's authorized_keys at order time (setup mirrors it to `sure`). `ssh root@<ip>` always works; pull-backup accepts `root@<ip>` too. |
| `/up` never healthy | `docker compose logs web` — usually a missing `.env` value; compare against `.env.example`. |
| `plaid:sandbox_smoke` skips | It needs `PLAID_CLIENT_ID`/`PLAID_SECRET`/`PLAID_ENV=sandbox` set + `docker compose up -d`. Exit 0 without them is expected. |
| Plaid OAuth loop/error | Redirect URI must be exactly `https://money.tayden.dev/accounts` in the dashboard AND match `APP_DOMAIN`/`PLAID_REDIRECT_URI` in `.env`. |
| Institution won't link | Check the table in step 7 — some are manual by design. Nothing is lost: manual account or CSV. |
| Duplicates after first bank sync | Expected — `monarch:dedup` → `/dedup/candidates`. Provider rows win merges. |
| Re-run import | `monarch:revert` first (full delete of imported records), then re-import. |
| Restore a backup | `cd /opt/sure/deploy/vps && ./bin/restore` (latest) or `./bin/restore backups/<file>.dump` — it stops web/worker, restores, restarts. |
| Want factory reset | `cd /opt/sure/deploy/vps && docker compose down -v` (deletes DB+volumes) → re-run `setup-vps`. `./bin/backup` FIRST. |
| Docs needed mid-flow | `docs/setup/VPS.md` (kit), `docs/setup/PLAID.md` (Plaid detail), `docs/monarch-import/RUNBOOK.md` (import detail), `docs/REHEARSAL.md` (what was proven). |

## OS note

Setup targets **Ubuntu 26.04 LTS** (what OVH ships). The script detects the
release via `/etc/os-release` and probes Docker's apt repo for the matching
codename, falling back to `noble` (24.04) only if Docker hasn't published your
release yet — so it also works on 24.04/25.x unmodified. The rehearsal ran on
Ubuntu 22.04; see `docs/REHEARSAL.md` §VPS for the exact delta.
