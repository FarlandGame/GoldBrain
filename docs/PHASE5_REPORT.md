# GoldBrain Phase 5 — Backend Core Audit

Date: 2026-09-12  
Branch: `backend/phase4-market-data-validation`

## Database

`0009_phase5_backend_core` is the new head migration. It creates
`market_assets`, `watchlists`, `user_preferences` and `model_versions`, seeds
the three MVP assets, and converts persisted price, candle, forecast,
evaluation, alert and paper-trading values from binary `FLOAT` to PostgreSQL
`NUMERIC`. A clean SQLite migration was run from base to head and back to
base; PostgreSQL SQL was also generated successfully with the PostgreSQL
dialect. A live PostgreSQL server was not available on the audit host (Docker
and `psql` are not installed), so a real server execution still needs to be
run on the deployment host.

## Auth

Registration and login use Argon2id hashes, normalized email addresses and a
10–128 character password policy. Access JWTs are short-lived. Refresh tokens
are rotated and only SHA-256 hashes are stored. Sessions can be listed and
revoked, `POST /auth/logout` accepts either the current access token or a
refresh token, and `POST /auth/logout-all` revokes every active session.
Password-reset tokens are stored hashed in `account_tokens`; development can
return a debug token, while production never pretends to deliver email.
Registration handles the unique-email race transactionally. A process-local
failed-login lock and the existing request limiter provide private-beta
brute-force protection; a shared Redis limiter is still needed for a
multi-worker public deployment.

## Market providers

### BTC

- Live provider: Wallex `GET /v1/markets`, REST polling at a configured 60-second worker interval.
- Historical provider: Wallex `GET /v1/udf/history` for `1m`, `1h` and `1d` candles.
- Currency/unit: `USDT` / `coin`; market `GLOBAL`.
- Fallback: Nobitex stats, then ZARIX/Gold API where a compatible quote exists.
- Audit observation: real HTTP 200 returned BTC `77410.8` at backend receipt
  `2026-09-12T16:38:13Z`; Wallex did not publish a per-ticker source
  timestamp, so source age is bounded by receipt time rather than claimed as
  provider time. Measured request latency was about 9.2 seconds in that run.
- Status: available, but REST polling and missing provider timestamps prevent
  calling it a true streaming feed.

### USDT

- Live provider: Wallex `GET /v1/markets`, REST polling at 60 seconds.
- Historical provider: Wallex UDF `USDTTMN`, with the same supported resolutions.
- Currency/unit: `IRT` (toman) / `coin`; market `IRAN`.
- Fallback: Nobitex `usdt-rls` (IRR is converted once at the provider edge),
  Navasan, then ZARIX.
- Audit observation: a real response returned USDT `233652` at backend
  receipt `2026-09-12T16:38:15Z`; source timestamp was absent. Nobitex's documented
  stats limit is 20 requests/minute and UDF limit 60 requests/minute; the
  service keeps fallback requests bounded and records their use.
- Status: available through the primary REST snapshot; source-time accuracy
  and upstream rate-limit terms require production monitoring.

### GOLD18

- Live primary: Navasan `GET /latest/` when `NAVASAN_API_KEY` is configured.
- Fallback: PersianToolbox market reference, then ZARIX. The fallback source
  is visibly marked `UNVERIFIED` and `gold18_source_not_tradable`.
- Currency/unit: canonical `IRT` (toman) / `gram_18k`; market `IRAN`, purity
  `18K`. IRR→IRT conversion is centralized in `normalize_iranian_price`.
- Historical provider: none approved. The worker can derive complete candles
  only from persisted, timestamped live quotes; no history is fabricated.
- Audit observation: Navasan previously returned a real 18ayar value
  `23927700 IRT` with source timestamp `15:20:10Z`; at receipt `15:25:58Z`
  its age was ~349s and therefore stale. The latest real fallback response
  returned `19860175.9 IRT/gram` from PersianToolbox (provider timestamp
  `16:35:29Z`, receipt `16:38:17Z`, age ~168s); it is FRESH but remains
  unverified.
- Status: live reference available, but not reliable/tradable enough to start
  forecast collection until a licensed 18K historical/live source is approved.

## API and client contract

The existing routes remain compatible. Phase 5 adds single-asset aliases
`/market/{asset}/quote`, `/market/{asset}/candles`, plural forecast aliases,
`/forecast-performance`, persisted `/watchlist` and `/preferences`, and a
shared `error` object alongside the legacy `detail` field. No provider or AI
secret is exposed to Flutter.

## Tests

- Backend pytest: **39 passed, 0 failed, 1 deprecation warning**.
- Ruff (`app migrations tests`): **all checks passed**.
- Mypy (`app migrations`): **no issues in 77 source files**.
- Clean migration: **base → 0009 head succeeded**; downgrade back to base
  also succeeded on SQLite. PostgreSQL SQL compilation succeeded, but no
  PostgreSQL daemon was available for an execution test.
- Added integration coverage for registration, duplicate registration,
  login/session identity, refresh rotation and reuse rejection, logout via
  refresh token, logout-all, protected routes and persisted watchlist.
- Existing provider tests continue to cover provider-down, timeout, rate
  limit, invalid/stale data, fallback provenance, duplicate candles,
  out-of-order data, historical gaps and currency/unit mismatch.
- Runtime telemetry after the smoke run recorded Wallex 85% success / 7.2s
  average latency, Navasan 86.7% / 2.3s, PersianToolbox 85.3% / 4.4s and
  Nobitex 0% in this network environment; 186 fallback requests and 3 stale
  observations were visible in the observability endpoint.

## Remaining problems

1. Docker/PostgreSQL was unavailable on the audit machine, so deployment must
   run `docker compose up --build` and execute a real PostgreSQL migration and
   E2E flow before release sign-off.
2. Wallex live snapshots have no provider timestamp and measured latency can
   be several seconds; a WebSocket/streaming adapter or a timestamped paid
   feed is required for a stronger live guarantee.
3. Gold18 has no approved historical provider. PersianToolbox is diagnostic
   only, and Navasan freshness depends on a valid key and its plan limits.
4. Rate limiting is process-local. Replace it with Redis before running more
   than one public worker.
5. The existing Windows launcher can start duplicate Uvicorn processes if run
   repeatedly; operational hardening is still required.

The market layer is sufficient to persist and audit real BTC/USDT snapshots
and Wallex history. It is **not yet sufficient for claiming reliable
three-asset forecast collection**: Gold18 historical evidence and timestamped
low-latency live data remain open gates.
