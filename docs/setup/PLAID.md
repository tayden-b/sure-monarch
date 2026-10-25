# Plaid — self-hosted setup (single owner, Mac + Tailscale)

This is the exact checklist to connect Sure (running on your Mac behind Tailscale)
to your US financial institutions through Plaid. It assumes:

- Sure runs in Docker on the Mac (`web` on `:3000`, plus `worker`, `db`, `redis`).
- The Mac is on your tailnet; `tailscale serve`/`funnel` are available.
- A free Plaid **Trial plan** (US/CA only): real production data, **10 Items max**.
  `/item/remove` does **not** free a slot — don't burn Items experimenting.

## What gets exposed and why

| Piece | How | Needed for |
|---|---|---|
| `https://<mac>.<tailnet>.ts.net` (tailnet-only) | `tailscale serve` | You browsing Sure over HTTPS |
| Same hostname, **public** | `tailscale funnel` | Plaid webhooks + OAuth redirect URIs |

You can browse Sure on `localhost` or the tailnet name either way — the env vars
below are what tell Plaid where to send traffic, independent of how you browse.

## 1. Create the Plaid account and app

1. Sign up at https://dashboard.plaid.com/signup (US or Canada only).
2. Verify the email. Skip the "production access" prompts for now.
3. In the dashboard create/open your app (any name/logo works — Sure passes
   `client_name: "Sure Finances"` to Link regardless).

## 2. Verify Sandbox end-to-end first (no real accounts touched)

4. Go to https://dashboard.plaid.com/developers/keys and copy `client_id` and
   the **sandbox** `secret` into `.env`:
   ```
   PLAID_CLIENT_ID=<client_id>
   PLAID_SECRET=<sandbox secret>
   PLAID_ENV=sandbox
   ```
5. `docker compose up -d` (or `docker compose restart web worker`).
6. `docker compose exec web bin/rails plaid:sandbox_smoke` — creates a Sandbox
   Item (Plaid's "First Platypus Bank" test institution), runs a full sync, and
   asserts accounts, transactions, and holdings land. All DB writes are rolled
   back; expect `SUCCESS: Plaid Sandbox smoke test passed`. If this fails, stop
   here — nothing downstream will work.

## 3. Stand up Tailscale Serve + Funnel

7. On the Mac:
   ```
   tailscale serve --bg https+insecure://localhost:3000   # tailnet-only HTTPS
   tailscale funnel --bg https://localhost:3000           # public on port 443
   tailscale funnel status                                # confirm it's on
   ```
   Your public URL is `https://<mac>.<tailnet>.ts.net` (check `tailscale status`
   for the exact name).
8. Add to `.env`:
   ```
   APP_HOST=https://<mac>.<tailnet>.ts.net
   ```
   That derives the redirect URI (`$APP_HOST/accounts`) and webhook URL
   (`$APP_HOST/webhooks/plaid`). If you ever route differently, set
   `PLAID_REDIRECT_URI` / `PLAID_WEBHOOK_URL` explicitly instead.
9. `docker compose restart web`.

Security note: Funnel makes the whole app publicly reachable — Sure's own
sign-in is the only gate, so use a strong password before enabling it. If you'd
rather not leave Funnel on permanently, you can enable it only while linking
OAuth institutions; webhooks then silently stop arriving and you'll rely on the
manual **Sync** button (webhook delivery resumes when Funnel is back on).

## 4. Allowlist URLs in the Plaid dashboard

10. At https://dashboard.plaid.com/developers/api → **Configure** next to
    *Allowed redirect URIs*, add exactly:
    `https://<mac>.<tailnet>.ts.net/accounts`
    (must match `PLAID_REDIRECT_URI` / `$APP_HOST/accounts` **exactly** — no
    trailing slash, https).
11. There is **no** dashboard allowlist for webhook URLs — the webhook URL is
    sent to Plaid inside each Link token. If you set `PLAID_WEBHOOK_URL`, make
    sure it's the Funnel URL; otherwise `$APP_HOST/webhooks/plaid` is used.

## 5. Products + Trial production access

12. Sure requests `transactions`, `investments`, and `liabilities` per linked
    account (all three are on the free Trial plan; `auth`/routing numbers are
    optional — Sure doesn't require them).
13. Request production access from the dashboard (**Get production access**).
    Pick the **Trial plan** — free, no security questionnaire, US/CA
    institutions only. Approval is typically quick.
14. Switch `.env` to the **production** secret + `PLAID_ENV=production` and
    restart `web worker`.

## 6. Link your institutions (one Plaid Item per login)

Expected Item usage ≈ 6 of your 10 Trial slots:

| Institution | Plaid login | Items | Notes |
|---|---|---|---|
| Chase (checking/savings/cards) | chase.com — OAuth | 1 | OAuth redirect goes through the Funnel URL |
| American Express | americanexpress.com — OAuth | 1 | |
| SoFi (checking/savings) | sofi.com | 1 | |
| Fidelity (brokerage, Roth IRA, HSA) | fidelity.com — OAuth | 1 | Workplace accounts may need **Fidelity NetBenefits** — a separate Plaid institution; if its page doesn't support Investments or the account won't link, use manual accounts |
| Fidelity 401(k)s / pension | netbenefits.com | 1 (maybe 0) | Coverage varies; treat as likely-manual |
| Morgan Stanley at Work / EquatePlus | — | 0 | Equity-plan accounts are generally not linkable via Plaid → create them as manual Investment accounts |
| Gemini credit card | gemini.com | 1 if offered | Plaid's Gemini entry is for the exchange; the WebBank credit card may not link → manual CreditCard if absent |
| Robinhood | robinhood.com — OAuth | 1 | |

15. In Sure: **Accounts → Link account → Plaid** and walk each institution.
    OAuth institutions will bounce you to the bank's site and back to
    `https://<mac>.<tailnet>.ts.net/accounts`.
16. If a connection degrades (bank password change, MFA churn), Sure marks the
    item **requires update** — use the reconnect action, which opens Plaid Link
    in update mode (no new Item is consumed; the same access token is healed).

## 7. Crypto exchanges — use direct providers, not Plaid

- **Coinbase**: Accounts → Link account → Coinbase. Create a **CDP API key** at
  https://portal.cdp.coinbase.com/access/api with **View (read-only)**
  permission only. Paste the key name and the EC private key (PEM block) —
  single-line `\n`-escaped secrets are accepted.
- **Kraken**: Accounts → Link account → Kraken. In Kraken → Settings → API,
  generate a key with **Query Funds** and **Query Closed Orders & Trades**
  (both required); **Query Ledger Entries** recommended (its absence is skipped
  gracefully). Leave every trade/withdraw/deposit permission **off**.
- **Gemini exchange**: no provider exists — do not expect one; track via a
  manual account or CSV import.

## Env vars reference

| Var | Required | Purpose |
|---|---|---|
| `PLAID_CLIENT_ID`, `PLAID_SECRET` | yes | dashboard → Keys; match the env |
| `PLAID_ENV` | yes | `sandbox` then `production` |
| `APP_HOST` | recommended | public origin, e.g. `https://<mac>.<tailnet>.ts.net` |
| `PLAID_REDIRECT_URI` | optional | exact redirect URI; default `$APP_HOST/accounts` |
| `PLAID_WEBHOOK_URL` | optional | exact webhook URL; default `$APP_HOST/webhooks/plaid` |
| `PLAID_HISTORY_DAYS` | optional | first-link backfill; default 730 (Plaid's max) |

## Verify it's working

- `docker compose exec web bin/rails plaid:sandbox_smoke` (Sandbox creds).
- After linking a real institution: `docker compose logs -f worker` shows the
  sync; `docker compose logs web | grep webhooks` shows Plaid webhook posts
  (`TRANSACTIONS/SYNC_UPDATES_AVAILABLE`, `HOLDINGS/DEFAULT_UPDATE`).
- A webhook that can't be verified is rejected 400 and logged — if webhooks
  never arrive, check Funnel is on and the URL in the Plaid dashboard under the
  item's webhook config matches `$APP_HOST/webhooks/plaid`.
