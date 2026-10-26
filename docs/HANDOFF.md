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
  - SSH key: **OVH (US) does not offer an SSH-key field at checkout** — it
    emails a temporary password for the `ubuntu` user instead (which arrives
    already expired). First login flow is in step 3.
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

## 3. First login + install the app (~20 min, mostly a build)

```bash
# ⌨️ from your laptop — log in as `ubuntu` (NOT root; root has no keys on OVH).
# The emailed temporary password is expired: ssh prompts for it once, then
# forces you to pick a new password on the spot.
ssh ubuntu@<vps-public-ipv4>
```

```bash
# ⌨️ back on your laptop — install your key for the ubuntu user so future
# logins (and the setup script's key mirroring) are passwordless:
ssh-copy-id -i ~/.ssh/id_ed25519.pub ubuntu@<vps-public-ipv4>
```

```bash
# 🖥️ on the VPS (as `ubuntu` — it has sudo)
sudo apt-get update && sudo apt-get install -y git
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
# 🖥️ on the VPS (as ubuntu + sudo, or `ssh sure@<ip>` without it)
cd /opt/sure/deploy/vps
sudo sed -i 's/^ONBOARDING_STATE=.*/ONBOARDING_STATE=closed/' .env
sudo docker compose up -d
```

- 🖱️ Turn on 2FA: app → **Settings → Security → Multi-factor authentication** —
  scan the TOTP QR into your authenticator app.

## 5. Import your Monarch history (~10–20 min)

`deploy/vps/data/archive/` is bind-mounted read-only at `/archive` in the app,
and it is owned by the app's container uid (1000, `rails`) — not by `ubuntu`
or `sure`. So stage the export in your home dir, then root-copy it in and
hand it to the app uid:

```bash
# ⌨️ from your laptop — stage the export in your home dir on the VPS
scp -r /path/to/monarch-export/ ubuntu@<vps-public-ipv4>:~/
```

```bash
# 🖥️ on the VPS — copy it in and fix ownership for the container uid
sudo cp -r ~/monarch-export/. /opt/sure/deploy/vps/data/archive/
# the files must land as /opt/sure/deploy/vps/data/archive/import/*.json
sudo /opt/sure/deploy/vps/bin/fix-archive-perms   # chown -R <app uid> + modes
```

```bash
# 🖥️ on the VPS (docker needs root or the `sure` user — `ssh sure@<ip>` works too)
cd /opt/sure/deploy/vps
# dry run first — writes nothing, prints the reconciliation report
sudo docker compose exec -T web bin/rails "monarch:import[/archive,dry_run]"
# real run
sudo docker compose exec -T web bin/rails "monarch:import[/archive]"
# cross-source duplicate scan — prints counts + a review URL if it finds pairs
sudo docker compose exec -T web bin/rails monarch:dedup
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
  key="${kv%%=*}"; grep -q "^${key}=" .env && sudo sed -i "s|^${key}=.*|${kv}|" .env || echo "$kv" | sudo tee -a .env
done
sudo docker compose up -d
# optional sanity pass first: PLAID_ENV=sandbox + sandbox keys, then
#   docker compose exec -T web bin/rails plaid:sandbox_smoke
```

- 🖱️ Plaid dashboard → **Team settings → API → Allowed redirect URIs**: add
  `https://money.tayden.dev/accounts` (https, no trailing slash).
- `PLAID_REDIRECT_URI` and `PLAID_WEBHOOK_URL` were auto-derived from
  `APP_DOMAIN` in `.env` (`https://money.tayden.dev/accounts` and
  `.../webhooks/plaid`) — no manual edit needed unless you change the hostname.

## 7. Link everything (~15 min)

**Before linking, set the Plaid history window.** `PLAID_HISTORY_DAYS` (blank =
730, Plaid's max) controls how far back the first `/transactions/sync` and
investment-transactions pull reaches. Cover only the gap since the Monarch
archive's as-of date plus a ~45-day buffer — the imported archive ends
2026-09-29, so days-since + 45 ≈ **75** is enough. A short window keeps the
overlap (and the dedup workload) small; dedup still clears whatever lands in
it. Set it in `/opt/sure/deploy/vps/.env` and `sudo docker compose up -d`
before the first link, then raise/remove it afterwards if you want deeper
history.

```bash
echo "PLAID_HISTORY_DAYS=75" >> /opt/sure/deploy/vps/.env
sudo docker compose up -d
```

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

**What the first sync does now:** each provider account auto-attaches to the
imported account it matches — by the `(...1234)` mask in the imported name,
else by the Monarch payload mask, else by a unique institution match — so the
feed lands on the account that already holds your history instead of creating
a duplicate. Anything it can't identify creates a new account; for those,
open the imported account → **Link provider** → pick the Plaid account
(marked "Currently linked to …") and its feed moves over and the empty
sync-created account is removed. Ops equivalent:
`bin/rails "providers:attach[<plaid_account_id>,<account_id>]"`.

🖱️ After each link: watch the first sync land — `docker compose logs -f worker`.
Exact-overlap pairs (same account, same amount, ≤1 day apart, near-identical
names) merge automatically with the provider row winning — check
`DebugLogEntry` / worker logs for the merged count. Then re-run
`monarch:dedup` and clear `/dedup/candidates` for whatever judgment calls
remain (imported history meeting live feed is where duplicates appear;
provider rows win merges — correct). Auto-merge is a per-family flag
(`families.auto_merge_duplicates`, on by default) that only ever removes
`source=monarch` rows — two provider rows are never auto-merged.
The scan flags cross-source pairs only — Monarch rows vs the new provider
feed, or manual/CSV rows vs anything. It does NOT flag two rows from the
same provider's own feed: same `source` + own `external_id`s = real
transactions, not dupes.

## 8. Safety net (~5 min)

```bash
# 🖥️ on the VPS (bin/backup needs docker — run it with sudo or `ssh sure@<ip>`)
cd /opt/sure/deploy/vps
sudo ./bin/backup       # first snapshot now — backups/*.dump, keeps last 14
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

## Agents / MCP (optional)

External AI agents — a Devin workspace, Claude.ai, scripts, scheduled jobs —
can query Sure through `POST /mcp`. Interactive clients use the built-in OAuth
flow (Settings → MCP has the URL; nothing to configure). Unattended agents
authenticate with a static bearer token that acts as your user:

```bash
# 🖥️ on the VPS — generate one token per scope you need
openssl rand -hex 32
```

```bash
# 📝 /opt/sure/deploy/vps/.env — then `sudo docker compose up -d`
MCP_USER_EMAIL=<your Sure login email>
MCP_API_TOKEN_READONLY=<hex>   # read-only: get_*/list_*/search_* tools only
MCP_API_TOKEN=<hex>            # read + write: the full tool registry
```

**Hand the read-only token to anything unattended** — write tools are hidden
from its tool list and answer "Unknown tool" if called anyway. Keep read +
write for interactive assistants you trust to change data (create/update
transactions, update budgets, import statements). Settings → MCP shows which
token modes are configured, masked. Full detail: `docs/hosting/mcp.md`.

## If something breaks

| Symptom | Fix |
|---|---|
| `setup-vps` dies early | It's idempotent — fix the cause, re-run it. apt lock errors mean `unattended-upgrades` is still running; wait a minute. |
| Cert not issued / self-signed warning | DNS A record must resolve to the VPS + ports 80/443 open. `docker compose logs caddy` shows ACME errors. sslip.io is often LE-rate-limited — use a real domain. |
| `ssh sure@<ip>` denied | `sure` gets keys mirrored from BOTH root's and the login user's (`ubuntu`) `authorized_keys` — re-run `sudo deploy/vps/bin/setup-vps` after `ssh-copy-id`, or append your pubkey to `~sure/.ssh/authorized_keys` by hand. `ssh root@<ip>` does NOT work (PermitRootLogin is `prohibit-password` and OVH ships no root keys). |
| `/up` never healthy | `docker compose logs web` — usually a missing `.env` value; compare against `.env.example`. |
| `plaid:sandbox_smoke` skips | It needs `PLAID_CLIENT_ID`/`PLAID_SECRET`/`PLAID_ENV=sandbox` set + `docker compose up -d`. Exit 0 without them is expected. |
| Plaid OAuth loop/error | Redirect URI must be exactly `https://money.tayden.dev/accounts` in the dashboard AND match `APP_DOMAIN`/`PLAID_REDIRECT_URI` in `.env`. |
| Institution won't link | Check the table in step 7 — some are manual by design. Nothing is lost: manual account or CSV. |
| Duplicates after first bank sync | Expected — `monarch:dedup` → `/dedup/candidates`. Provider rows win merges. Two rows from one provider's own feed are never flagged (real transactions, not dupes); `SAME_SOURCE=1` re-enables same-store pairs for a CSV-double-upload cleanup. |
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
