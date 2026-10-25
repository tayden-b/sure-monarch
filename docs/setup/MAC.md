# Sure on a Mac — self-host kit

One-command setup for running this Sure fork on your Mac with Docker Desktop,
reachable over HTTPS from your phone via Tailscale. Everything lives under
`deploy/mac/` in the repo.

Target: a single technical owner. ~15 minutes first time.

## Prerequisites

1. **Docker Desktop for Mac** — https://docs.docker.com/desktop/install/mac-install/
   - Start it once, then: Docker Desktop → **Settings → General → "Start Docker
     Desktop when you sign in"** (required for the login-time autostart).
   - Apple Silicon is fine — the base image (`ruby:3.4.9-slim`) is multi-arch.
2. **Tailscale** (for phone/remote HTTPS access) — https://tailscale.com/download/mac
   - Sign in, and add the Tailscale app to your phone from the same tailnet.
   - The free tier covers a single-user tailnet.

## First-time setup (≈15 min)

1. Clone / update the repo and enter the kit directory:
   ```bash
   cd sure-monarch/deploy/mac
   ```
2. Run the setup script:
   ```bash
   ./bin/setup-mac
   ```
   It will:
   - verify Docker Desktop is running (and Tailscale, if installed),
   - create `.env` and generate `SECRET_KEY_BASE`, `POSTGRES_PASSWORD`, and the
     three Active Record encryption keys,
   - prompt for the few things that need an external account — all optional,
     press Enter to skip: `OPENAI_ACCESS_TOKEN` (platform.openai.com/api-keys),
     `TWELVE_DATA_API_KEY` (twelvedata.com), `PLAID_CLIENT_ID`/`PLAID_SECRET`
     (dashboard.plaid.com/developers/keys — Sandbox keys first),
   - `docker compose build` + `up -d` (first build is 10–20 min),
   - run `db:prepare`, wait for the health check, print your URLs.
3. Open **http://localhost:3000**, create your account (first user becomes the
   instance admin).
4. Lock onboarding afterwards: in `deploy/mac/.env` set `ONBOARDING_STATE=closed`,
   then `docker compose up -d`.
5. **(Remote access)** Expose HTTPS over your tailnet:
   ```bash
   ./bin/tailscale-expose
   ```
   This runs `tailscale serve` so `https://<machine>.<tailnet>.ts.net` proxies
   to the app, writes the matching `APP_DOMAIN`, `RAILS_ASSUME_SSL` and Plaid
   URLs into `.env` for you — then restart once with `docker compose up -d`.
   The `https://` URL works from your Mac and your phone (any tailnet device).
6. **(Plaid, optional)** For live bank syncs Plaid needs two publicly reachable
   paths — the webhook it posts sync events to and the OAuth redirect target:
   ```bash
   ./bin/tailscale-expose --funnel
   ```
   That exposes **only** `/webhooks/plaid`, `/webhooks/plaid_eu` and `/accounts`
   on the public internet; everything else stays tailnet-only. The script already
   wrote `PLAID_REDIRECT_URI`/`PLAID_WEBHOOK_URL`/`APP_DOMAIN` into `.env` —
   restart with `docker compose up -d` if you haven't since step 5. Then in the
   Plaid dashboard → **Team settings → API → Allowed redirect URIs**, add:
   `https://<machine>.<tailnet>.ts.net/accounts`
   Funnel must be allowed in your tailnet ACLs — see the error/help output of
   `tailscale funnel status` or https://tailscale.com/kb/1223/funnel.
7. **(Autostart + backups, optional)**:
   ```bash
   ./bin/install-launchd
   ```
   Installs two LaunchAgents: compose `up -d` at login, and `./bin/backup`
   nightly at 03:15 (logs in `deploy/mac/log/`). Remove with
   `./bin/install-launchd --uninstall`.
8. **(Monarch import)** Put your Monarch export directory in
   `deploy/mac/data/archive/` — it is mounted read-only at `/archive` inside the
   app (`MONARCH_ARCHIVE_PATH` in `.env`). The layout the importer expects is in
   `docs/monarch-import/SCHEMA.md` (`import/*.json`, `monarch.sqlite`, etc.).

## Daily operation

```bash
cd deploy/mac
docker compose ps            # status
docker compose logs -f web   # app logs (worker/db/redis similarly)
docker compose up -d         # apply .env changes / restart
docker compose stop          # stop (data persists)
docker compose down          # stop + remove containers (volumes/data persist)
```

## Upgrade

```bash
cd sure-monarch && git pull
cd deploy/mac
docker compose build          # rebuild the image
docker compose up -d          # restarts; bin/docker-entrypoint migrates the DB
./bin/backup                  # recommended BEFORE upgrading
```

## Backup / restore

- `./bin/backup` — `pg_dump -Fc` into `backups/sure-<timestamp>.dump`, keeps the
  last 14. `--with-storage` also archives the uploaded-files volume.
- `./bin/restore [file.dump]` — stops web/worker, `pg_restore --clean`, restarts.
  With no argument it restores the newest dump. It asks for confirmation.
- The launchd backup job runs `./bin/backup` nightly at 03:15 once installed.
- `./backups/` is on your disk — copy it somewhere off-machine for real safety.

## Troubleshooting

| Symptom | Check |
|---|---|
| `docker info` fails | Open Docker Desktop, wait for the whale to go steady. |
| First build fails on image pull (HTTP 429) | Docker Hub rate limit — wait a few minutes and re-run `docker compose build`. |
| App not healthy | `docker compose logs web` — look for missing `SECRET_KEY_BASE`/DB creds. |
| Redirects/links point at `https://localhost` and fail | `RAILS_ASSUME_SSL=true` is set but you're browsing plain `http://localhost`. Either browse the tailnet `https://` URL, or set `RAILS_ASSUME_SSL=false` for local-only use and restart. |
| Login works locally but not on tailnet | Make sure `bin/tailscale-expose` ran (it sets `RAILS_ASSUME_SSL=true`) and you ran `docker compose up -d` after. Check `tailscale serve status` shows the proxy. |
| Plaid "link account" missing | `PLAID_CLIENT_ID`/`PLAID_SECRET`/`PLAID_ENV` must be set (Settings → Providers shows the same fields). Sandbox keys only work with `PLAID_ENV=sandbox`. |
| Webhooks not arriving | Plaid must reach the public funnel path — `./bin/tailscale-expose --funnel` and check `tailscale funnel status`. |
| "This site can't be reached" at login | Docker Desktop may still be starting; `com.sure-mac.stack` waits ~3 min for it. Check `deploy/mac/log/stack.log`. |
| Need a clean slate | `docker compose down -v` deletes the DB/storage volumes — run `./bin/backup` first. |

## Files

```
deploy/mac/
  docker-compose.yml     web + worker (Sidekiq) + postgres + redis
  .env.example           every variable, annotated — copy to .env
  bin/setup-mac          one-command setup
  bin/tailscale-expose   tailnet HTTPS (+ optional public funnel for Plaid paths)
  bin/backup, bin/restore
  bin/install-launchd    login autostart + nightly backup agents
  launchd/               the two plist templates
  data/archive/          put the Monarch export here → /archive in containers
  backups/               pg_dump output (gitignored)
```
