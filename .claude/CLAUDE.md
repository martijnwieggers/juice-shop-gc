# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

**Important**: The primary authoritative source for all AI contributions is the [root AGENTS.md](../AGENTS.md). Please refer to that file for comprehensive guidelines, project overview, and shared skills.

**Skill Discovery**: Before performing any task, check if a matching skill exists by reading the `Skills` section of [AGENTS.md](../AGENTS.md). If a relevant skill is found, read and follow its `SKILL.md` from `.ai/skills/` before proceeding.

## Project Overview

OWASP Juice Shop is an **intentionally insecure** web application for security training. It combines an Express/Node.js backend with an Angular 21 frontend. The app has ~100+ built-in hacking challenges; intentional vulnerabilities are a feature, not a bug.

- Node.js 22–26 (default: 24), TypeScript throughout
- Backend: Express + SQLite/Sequelize (relational data) + MarsDB (MongoDB-like, for reviews/orders)
- Frontend: Angular 21 with Angular Material M3 (standalone + lazy-loaded modules)
- Code style: JS Standard Style enforced by ESLint (neostandard)

## Commands

```bash
# Install everything (also builds frontend + server)
npm install

# Development (hot-reload backend + frontend dev server)
npm run serve:dev

# Production build
npm run build          # builds both frontend and server TypeScript
npm run build:frontend # Angular production build
npm run build:server   # tsc compilation only

# Start production build
npm start              # runs build/app (requires prior build)

# Lint
npm run lint           # ESLint + frontend Angular/SCSS lint + config lint
npm run lint:fix       # auto-fix linting issues

# Testing
npm test                    # frontend + server + API tests (full suite)
npm run test:server         # server unit tests (Node.js built-in test runner)
npm run test:api            # API integration tests (Supertest)
npm run test:frontend       # Angular unit tests (Vitest)
npm start & npm run test:e2e  # Cypress E2E (requires running app)

# Single test file
node --import ./test/server/helpers/test-env.mjs --import tsx --test "test/server/path/to/file.unit.test.ts"
node --import ./test/api/helpers/test-env.mjs --import tsx --test "test/api/path/to/file.test.ts"

# Refactoring Safety Net
npm run rsn             # check RSN (must pass before committing challenge code changes)
npm run rsn:update      # update RSN cache after intentional changes
```

All commits must include DCO sign-off: `git commit -s -m "message"`

## Architecture

### Request Flow

```
Browser → Angular SPA (port 4200 in dev / built into dist/ in prod)
       → Express API (port 3000)
         ├── routes/*.ts          — individual route handlers
         ├── lib/insecurity.ts    — JWT auth, hashing, sanitization utilities
         ├── models/*.ts          — Sequelize models (SQLite)
         └── data/mongodb.ts      — MarsDB collections (reviews, orders)
```

**Entry points**: `app.ts` validates dependencies then delegates to `server.ts`. The `server.ts` file wires all middleware, routes, and Sequelize/MarsDB initialization before calling `datacreator.ts` to seed the database.

### Backend Structure

- **`routes/`** — one file per feature area; each exports handler function(s) registered in `server.ts`
- **`models/`** — Sequelize models for SQLite; relationships in `models/relations.ts`; `models/index.ts` exports shared sequelize instance
- **`lib/insecurity.ts`** — central security module: JWT sign/verify (intentionally weak RSA key exposed in source), MD5 hashing, HTML sanitization helpers
- **`lib/startup/`** — startup lifecycle: dependency validation → config validation → precondition checks → websocket registration → file restoration
- **`data/datacreator.ts`** — seeds all DB data on startup from static YAML/JSON definitions
- **`data/static/challenges.yml`** — single source of truth for all challenge metadata (name, category, difficulty, hints, key)
- **`data/static/codefixes/`** — TypeScript snippet files for the "Fix It" coding challenges; naming convention: `<challengeKey>_<N>[_correct].ts`
- **`config/`** — YAML configuration files (default, CTF, themes); loaded via the `config` npm package

### Frontend Structure

- **`frontend/src/app/`** — Angular components; one directory per route/feature
- **`frontend/src/app/app.routing.ts`** — all route definitions; Web3 features (faucet, wallet, sandbox) are lazy-loaded modules
- **`frontend/src/app/app.guard.ts`** — `LoginGuard`, `AdminGuard`, `AccountingGuard` route guards
- Angular Material M3 theming; custom themes in `frontend/src/theming/`
- i18n via `@ngx-translate`; translation strings live in `frontend/src/assets/i18n/` but must only be edited via [Crowdin](https://crowdin.com/project/owasp-juice-shop)

### Challenge System

Each challenge has:
1. A metadata entry in `data/static/challenges.yml` (key, name, category, difficulty, hints)
2. Detection logic in a route handler that calls `utils.solveIf()` or similar
3. Optional: coding challenge snippet + codefix files in `data/static/codefixes/`

The **Refactoring Safety Net (RSN)** (`rsn/`) compares current source snippets to a cached baseline to ensure that refactoring doesn't accidentally change challenge-relevant code without updating the corresponding codefix files. Run `npm run rsn` after any change to routes/models/lib code involved in coding challenges.

### Key Intentional Vulnerabilities (by design)

- `lib/insecurity.ts`: RSA private key hardcoded in source; old `jsonwebtoken` (0.4.0); MD5 passwords; `express-jwt` 0.1.3
- `sanitize-html` pinned to 1.4.2 (vulnerable version) for XSS challenges
- SQL injection via raw Sequelize queries in `routes/search.ts` and login
- NoSQL injection via MarsDB in `routes/showProductReviews.ts`

Do not "fix" these — they are the point of the application.

## Graafschap College Deployment

This fork adds classroom deployment support on top of the standard Juice Shop.

### Continue Code Isolation

The Hashids salts used for score export/import are configurable via environment variables, preventing scores from being imported across environments:

| Variable | Default (fallback) |
|---|---|
| `CONTINUE_CODE_SALT` | `'this is my salt'` |
| `CONTINUE_CODE_SALT_FINDIT` | `'this is the salt for findIt challenges'` |
| `CONTINUE_CODE_SALT_FIXIT` | `'yet another salt for the fixIt challenges'` |

Every import and export logs which salt was used (`info` level via Winston).

### Custom Config

`config/graafschap-college.yml` is a full copy of `config/default.yml` for classroom-specific overrides. Load it with `NODE_ENV=graafschap-college`.

### Single-container deployment

`docker-compose.yml` — starts one `juice-shop-gc` container with all configurable env vars documented as comments. Build and start:

```bash
docker compose build
docker compose up -d
```

### Multi-site classroom deployment

`generate-compose.sh` — interactive script that generates `docker-compose-gc.yml` with one container per student group and optionally configures Nginx Proxy Manager automatically via its REST API.

```bash
# vereist: jq (apt install jq)
bash generate-compose.sh
docker compose -f docker-compose-gc.yml up -d
```

The script:
- Detects NPM's Docker network automatically (`docker inspect npm`)
- Generates cryptographically random salts per site (`openssl rand -hex 20`)
- Sets `container_name` per site for predictable NPM DNS resolution
- Optionally creates proxy hosts + Let's Encrypt certificates via `http://127.0.0.1:81/api`

Each site is reachable as `js-<initialen>.wieggers.eu` via NPM on the shared `portainer_default` network. No host port mappings are used — NPM proxies directly to containers on port 3000.

### Database behaviour

`server.ts:734` calls `sequelize.sync({ force: true })` on every startup — all tables are dropped and reseeded. This is intentional upstream behaviour. Challenge progress is lost on container restart unless a volume is mounted at `/juice-shop/data/`.
