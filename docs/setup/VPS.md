# Sure on a VPS — self-host kit

One-command setup for running this Sure fork on a small public VPS
(Ubuntu 26.04 LTS, ~2 vCPU / 4 GB / 40 GB), with public HTTPS via Caddy +
Let's Encrypt. Everything lives under `deploy/vps/` in the repo.

Target: a single technical owner. ~20–30 min first time (most of it is the
image build). For the full ordered move-in checklist (DNS → account →
Monarch import → Plaid), use `docs/HANDOFF.md` — this page is the reference
for the kit itself.

## Prerequisites

1. **A VPS** — Ubuntu 26.04 LTS, x86_64, and SSH **key** access to a
   sudo-capable login user (the setup disables password SSH for everyone and
   refuses to run the sshd hardening step when no key exists). e.g. OVHcloud
   VPS-1 (2 vCPU / 4 GB / 40 GB NVMe) — note OVH US has no SSH-key field at
   checkout; you get an `ubuntu` user + emailed temp password, then
   `ssh-copy-id` your key over (see `docs/HANDOFF.md` step 3).
2. **A hostname** — a DNS **A record** pointing at the VPS's public IPv4,
   e.g. `money.tayden.dev`. Let's Encrypt needs it to issue a real cert.
   - No domain? `<vps-ip>.sslip.io` (e.g. `51.210.42.17.sslip.io`) resolves
     for free — but public Let's Encrypt on sslip.io hostnames frequently
     hits LE's per-domain rate limit; a real domain is strongly preferred.
   - Rehearsal/local testing: `APP_DOMAIN=localhost` — Caddy self-signs.
3. Port **80 and 443 inbound open** — LE's HTTP-01 challenge needs both.
   `ufw` is configured for you (22/80/443 only).

## First-time setup (≈20–30 min)

SSH in as the login user (`ubuntu` on OVH), then:

```bash
git clone --branch monarch-baseline https://github.com/tayden-b/sure-monarch.git /tmp/sure
sudo /tmp/sure/deploy/vps/bin/setup-vps
```

> `setup-vps` re-clones to its canonical location `/opt/sure` — `/tmp/sure`
> is only a bootstrap. Keep the whole command on one line.

The script is **idempotent** — re-run it any time. It will:

- apt update + install base packages, enable `unattended-upgrades`
  (nightly security patches),
- install Docker Engine + compose plugin from the official Docker apt repo,
- create a non-root `sure` user (docker group) — the stack runs as them,
- mirror the operator's SSH keys (root's AND the sudo user's
  `authorized_keys`) into `~sure` so `ssh sure@<ip>` works, and warn loudly
  if it finds none,
- `ufw`: allow 22/80/443, enable; `fail2ban` sshd jail; sshd
  `PasswordAuthentication no` + `PermitRootLogin prohibit-password` via
  `sshd_config.d/00-sure-hardening.conf` (the 00- prefix sorts ahead of
  cloud-init's `50-cloud-init.conf` — sshd keeps the FIRST value seen), then
  verifies with `sshd -T` and dies rather than leaving password auth on.
  Make sure your key works before logging out,
- clone the repo (`monarch-baseline`) into `/opt/sure` as `sure`,
- write `.env` — auto-generates `SECRET_KEY_BASE`, `POSTGRES_PASSWORD`, and
  the three Active Record encryption keys; derives `WEBAUTHN_RP_ID`,
  `WEBAUTHN_ALLOWED_ORIGINS`, `PLAID_REDIRECT_URI`, `PLAID_WEBHOOK_URL`
  from `APP_DOMAIN`,
- prompt only for what needs a human: `APP_DOMAIN`, then optional
  `OPENAI_ACCESS_TOKEN`, `TWELVE_DATA_API_KEY`,
  `PLAID_CLIENT_ID`/`PLAID_SECRET`/`PLAID_ENV` — Enter skips all optionals,
- `docker compose build` + `up -d` (first build is 10–20 min), wait for
  `web` `/up`, run `db:prepare`,
- install + enable systemd units: `sure.service` (compose up on boot) and
  `sure-backup.timer` (nightly 03:15 backup),
- print your URL and the next steps.

Open `https://<APP_DOMAIN>`, create your account (first user = admin),
then lock onboarding: set `ONBOARDING_STATE=closed` in
`/opt/sure/deploy/vps/.env` and `docker compose up -d`.

**Env overrides** (for rehearsal/automation): `SURE_HOME`, `SURE_USER`,
`SURE_REPO_URL`, `SURE_REPO_BRANCH`, `APP_DOMAIN` (skips the prompt).

## The stack

| Service | What | Exposed? |
|---|---|---|
| `caddy` | HTTPS termination + reverse proxy (`caddy:2-alpine`) | **Only** published ports: 80, 443 |
| `web` | Rails app (Puma) — image built from repo `Dockerfile` | internal `3000`, reached by Caddy |
| `worker` | Sidekiq (syncs, imports, recurring) | internal only |
| `db` | PostgreSQL 16, named volume | internal only — no host port |
| `redis` | Redis 7, named volume | internal only — no host port |

- `./data/archive` → read-only `/archive` in `web`/`worker`
  (`MONARCH_ARCHIVE_PATH=/archive`).
- `./backups` holds `pg_dump` output from `bin/backup` (and is also at
  `/backups` inside `db`).
- `caddy-data`/`caddy-config` volumes keep the issued certs across restarts.
- Login/credential throttling lives in the app (Rack::Attack), not Caddy.

## Daily operation

```bash
cd /opt/sure/deploy/vps
docker compose ps            # status (healthy per-service checks)
docker compose logs -f web   # app logs (worker/db/redis/caddy similarly)
docker compose up -d         # apply .env changes / restart
docker compose stop          # stop (data persists)
docker compose down          # stop + remove containers (volumes/data persist)
systemctl status sure.service sure-backup.timer
systemctl list-timers        # next backup run
```

## Upgrade

```bash
cd /opt/sure/deploy/vps && ./bin/upgrade
```

Takes a backup first, then `git pull --ff-only` on the checked-out branch →
rebuild → `up -d` → `db:prepare` → waits on `/up`.

## Backup / restore / off-box copies

- `./bin/backup` — `pg_dump -Fc` into `backups/sure-<timestamp>.dump`, keeps
  the last 14. `--with-storage` also archives the uploaded-files volume.
  `sure-backup.timer` runs it nightly at 03:15.
- `./bin/restore [file.dump]` — stops web/worker, `pg_restore --clean`,
  restarts. Newest dump by default; asks for confirmation.
- `./bin/pull-backup sure@<vps>` — run **from your laptop**: scp's the
  newest dump into `./backups-pulled/`. Off-box copies are what make the
  VPS replaceable — pull after any import/link milestone.
- Full reset: `docker compose down -v` (deletes the DB volume) → re-run
  `bin/setup-vps`. `./bin/backup` FIRST.

## Rehearsal / local mode

`APP_DOMAIN=localhost` gives you the entire stack with a self-signed cert —
no DNS needed. For a fake non-localhost hostname (e.g. `sure.test` in
`/etc/hosts`), set `CADDYFILE=./Caddyfile.internal` in `.env` (adds
`tls internal` so Caddy self-signs instead of hitting Let's Encrypt's
rate limiter).

## Troubleshooting

| Symptom | Check |
|---|---|
| `setup-vps` dies at Docker install | DNS/egress blocked — verify `curl -fsSL https://download.docker.com` works. |
| Browser shows "connection refused" | `docker compose ps` — is `caddy` up? `ufw status` — are 80/443 allowed? |
| Cert never issued / browser warns about self-signed | LE couldn't reach you: DNS A record must resolve to the VPS and ports 80/443 must be open. `docker compose logs caddy` shows ACME errors. sslip.io hostnames are often LE-rate-limited — use a real domain. |
| `https://` works but links redirect to `http://` | `RAILS_ASSUME_SSL`/`RAILS_FORCE_SSL` must stay `true` in `.env` (defaults). |
| App not healthy | `docker compose logs web` — usually a missing `.env` value; compare against `.env.example`. |
| Login loops or 403s on POST | You changed `APP_DOMAIN` — also update `WEBAUTHN_ALLOWED_ORIGINS`, `PLAID_REDIRECT_URI`, `PLAID_WEBHOOK_URL` and restart. |
| Plaid "link account" missing | `PLAID_CLIENT_ID`/`PLAID_SECRET`/`PLAID_ENV` must be set. Sandbox keys only work with `PLAID_ENV=sandbox`. |
| Webhooks not arriving | `PLAID_WEBHOOK_URL` must be `https://<APP_DOMAIN>/webhooks/plaid` and reachable — `curl -i https://<APP_DOMAIN>/webhooks/plaid` from off-box should return something other than a timeout. |
| Can't SSH after setup | Password auth is off by design — use the SSH key you provisioned (`ssh ubuntu@<ip>` or `ssh sure@<ip>`; root login is `prohibit-password` and OVH ships no root keys). If locked out entirely, use the provider's KVM/rescue console to revert `/etc/ssh/sshd_config.d/00-sure-hardening.conf`. |
| Importer can't read `/archive` | `./data/archive` must be owned by the app uid (1000). Run `sudo deploy/vps/bin/fix-archive-perms` after copying the export in. |
| Backup timer not running | `systemctl list-timers` → force a run: `sudo systemctl start sure-backup.service`; logs: `journalctl -u sure-backup.service`. |
| Need to roll back an upgrade | `./bin/restore` for the DB; `git -C /opt/sure checkout <old-sha>` + `./bin/upgrade` for the code. |

## Files

```
deploy/vps/
  docker-compose.yml        caddy + web + worker (Sidekiq) + postgres + redis
  Caddyfile                 auto-HTTPS + security headers + /healthz
  Caddyfile.internal        same + `tls internal` (self-signed rehearsal)
  .env.example              every variable, annotated — copy to .env
  bin/setup-vps             one-command setup (root, idempotent)
  bin/backup, bin/restore   pg_dump → ./backups (keep 14) / pg_restore
  bin/pull-backup           laptop-side: scp newest dump off the VPS
  bin/upgrade               backup → pull → rebuild → migrate → restart
  systemd/
    sure.service            compose up on boot
    sure-backup.service     runs bin/backup once
    sure-backup.timer       nightly 03:15
  data/archive/             put the Monarch export here → /archive in containers
  backups/                  pg_dump output (gitignored)
```
