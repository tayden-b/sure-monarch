# Contributing to Sure

It means so much that you're interested in contributing to Sure! Seriously. Thank you. The entire community benefits from these contributions!

## House Rules

- Before contributing, read the [repository guidance](AGENTS.md) and [architecture and conventions](docs/llm-guides/architecture.md). Detailed [task guides](docs/llm-guides/README.md) cover testing, UI, APIs and providers.
- Coding-assistant setup is optional; see the [supported instruction adapters](docs/llm-guides/harness-adapters.md).
- Before contributing, please check if it already exists in [issues](https://github.com/we-promise/sure/issues) or [PRs](https://github.com/we-promise/sure/pulls)
- Given the speed at which we're moving on the codebase, we don't assign issues or "give" issues to anyone.
- When multiple PRs are submitted for the same issue, we take the one that most succinctly & efficiently solves a given problem and stays within the scope of work.
- Priority is generally given to previous committers as they've proven familiarity with the codebase and product.

## What should I contribute?

As we are still in the early days of this project, we recommend [heading over to the Wiki](https://github.com/we-promise/sure/wiki) to get a better idea of _what_ to contribute.

In general, _full features_ that get us closer to [our 🔜 Vision](https://github.com/we-promise/sure/wiki/Vision) are the most valuable contributions at this stage.

## Development

### Setup

To get setup for local development, you have two options:

1. [Dev Containers](https://code.visualstudio.com/docs/devcontainers/containers) with VSCode (see the `.devcontainer` folder)
   - A `selenium/standalone-chrome` service is included in the Dev Container setup, so **system tests work out of the box** — no local Chrome required.
   - Run system tests: `DISABLE_PARALLELIZATION=true bin/rails test:system`
   - Watch the browser live at `http://localhost:7900` or `http://localhost:4444` (password: `secret`)

   <details>
   <summary>Running the devcontainer without VS Code (plain docker compose)</summary>

   ```sh
   cp .env.local.example .env.local
   cp .env.test.example .env.test
   docker compose -f .devcontainer/docker-compose.yml up -d --build
   docker compose -f .devcontainer/docker-compose.yml exec -T app bin/setup
   ```

   Then start the app. `bin/dev` works both interactively and detached —
   the Tailwind watcher stays alive without a TTY (it polls with
   `tailwindcss:watch[always]`):

   ```sh
   docker compose -f .devcontainer/docker-compose.yml exec app bin/dev
   ```

   For detached/non-interactive use (CI, scripts):

   ```sh
   docker compose -f .devcontainer/docker-compose.yml exec -dT app \
     bash -c 'nohup bin/dev > log/dev.log 2>&1 &'
   ```

   The setup above is the verified passing baseline — no keys needed.
   - `.env.test` sets `DATABASE_URL` to the devcontainer's postgres
     superuser (the suite needs it for fixture trigger handling). Required
     by tests that open a second PG session; for a local Postgres export
     `POSTGRES_USER`, `POSTGRES_PASSWORD`, `DB_HOST` or edit the URL.
   - Tests: `docker compose -f .devcontainer/docker-compose.yml exec -T app bin/rails test`
   - System tests: `docker compose -f .devcontainer/docker-compose.yml exec -T app env DISABLE_PARALLELIZATION=true bin/rails test:system`
   - Optionally load synthetic demo data (`user@example.com` / `Password1!`):
     `docker compose -f .devcontainer/docker-compose.yml exec -T app bin/rake demo_data:default`

   **Optional — disposable encryption keys (diagnostic path, not part of
   the passing baseline):**

   The app encrypts provider/API tokens at rest with
   `ACTIVE_RECORD_ENCRYPTION_*` keys. To exercise that locally, generate
   throwaway values inside the container and paste them into `.env.local`
   (see `.env.local.example`):

   ```sh
   docker compose -f .devcontainer/docker-compose.yml exec -T app bin/rails db:encryption:init
   ```

   Use disposable values only — never production keys, never committed
   `.env` files. **This setup is not approved for real financial data:**
   connect synthetic/demo accounts only. Encryption coverage is partial —
   enabling test keys turns on the encryption-gated tests, but upstream
   `encrypt_fixtures` double-encodes `encrypts` attributes on jsonb
   columns, so ~140 fixture reads raise
   `ActiveRecord::Encryption::Errors::Decryption` (an upstream bug, not a
   setup error). Leave the keys commented in `.env.test` for a green
   suite; the gated tests skip.

   </details>

2. Local Development
   - [Mac Setup Guide](https://github.com/we-promise/sure/wiki/Mac-Dev-Setup-Guide)
   - [Linux Setup Guide](https://github.com/we-promise/sure/wiki/Linux-Dev-Setup-Guide)
   - [Windows Setup Guide](https://github.com/we-promise/sure/wiki/Windows-Dev-Setup-Guide)

### Making a Pull Request

1. Fork the repo
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request, and be sure to check the [Allow edits from maintainers](https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/working-with-forks/allowing-changes-to-a-pull-request-branch-created-from-a-fork) option while creating your PR. This allows maintainers to collaborate with you on your PR if needed.
6. If possible, [link your pull request to an issue](https://docs.github.com/en/issues/tracking-your-work-with-issues/linking-a-pull-request-to-an-issue#linking-a-pull-request-to-an-issue-using-a-keyword) by adding the appropriate keyword (e.g. `fixes issue #XXX`)
7. Before requesting a review, please make sure that all [Github Checks](https://docs.github.com/en/rest/checks?apiVersion=2022-11-28) have passed and your branch is up-to-date with the `main` branch. After doing so, request a review and wait for a maintainer's approval.

All PRs should target the `main` branch.

### Automated Security Scanning

Every pull request to the `main` branch automatically runs a Pipelock security scan. This scan analyzes your PR diff for:

- Leaked secrets (API keys, tokens, credentials)
- Agent security risks (misconfigurations, exposed credentials, missing controls)

The scan runs as part of the CI pipeline and typically completes in ~30 seconds. If security issues are found, the CI check will fail. You don't need to configure anything—the security scanning is automatic and zero-configuration.
