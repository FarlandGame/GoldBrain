# GoldBrain

GoldBrain is a two-person financial-intelligence workspace being developed as a private beta before any public launch.

```text
GoldBrain/
├── frontend/          Flutter app (UI / client)
├── backend/           Python + FastAPI + ML/data services
├── docs/              Architecture, API contract, roadmap and handoff notes
├── scripts/           Local checks / backup helpers
└── docker-compose.yml PostgreSQL + backend for development
```

## Three-phase refactor status

- ✅ **Phase 1 — Foundation & Handoff**: repo cleanup, FastAPI, provider gateway, DB foundation, Flutter backend client.
- ✅ **Phase 2 — Intelligence Private Alpha**: OHLCV history, feature engine, Forecast V2, backtesting, evaluation ledger, backend news/deep analysis, paper trading.
- ✅ **Phase 3 — Product-Ready Private Beta Foundation**: users/sessions, Argon2 passwords, JWT + refresh rotation, device/session management, rate limiting, audit logs, alerts, entitlement interface, readiness checks, sandbox exchange contract.

Real-money exchange execution is intentionally **not enabled** in this repository. Paper Trading is the executable testing path.

## Backend quick start

```powershell
cd backend
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements-dev.txt
Copy-Item .env.example .env
alembic upgrade head
pytest -q
uvicorn app.main:app --reload
```

Development API docs: `http://127.0.0.1:8000/docs`

## Private-beta market cycle

The private beta currently covers Gold18, USDT and BTC. It is deliberately
**data collection and paper-trading only**: no command in this repository can
place a real-money exchange order.

After starting the backend and applying migrations, seed BTC/USDT hourly
history from Wallex once:

```powershell
cd backend
python -m app.jobs.backfill_wallex_history --symbol BTC --timeframe 1h --lookback-hours 720
python -m app.jobs.backfill_wallex_history --symbol USDT --timeframe 1h --lookback-hours 720
```

Then run the safe cycle periodically (for example, once per minute during a
supervised private test):

```powershell
python -m app.jobs.run_private_beta_cycle
```

For continuous supervised collection, run the worker in a separate terminal;
it repeats every 60 seconds by default (`GOLDBRAIN_MARKET_COLLECTION_INTERVAL_SECONDS`):

```powershell
python -m app.jobs.run_private_beta_worker
```

`Start-GoldBrain.ps1` starts this worker automatically and
`Stop-GoldBrain.ps1` stops it together with the app.

It collects verified market quotes, derives quote candles, generates an
auditable forecast when enough history exists, and evaluates forecasts whose
target time has passed. Provider failures are returned as issues and do not
fabricate prices. The Flutter dashboard should read the persisted result from
`GET /api/v1/market/overview`; opening the app does not trigger collection or
forecast generation.

Gold18 needs a fresh, licensed/source-approved Iranian quote provider. Until
one is configured, the cycle reports Gold18 as unavailable instead of deriving
a tradable forecast from stale data.

## Frontend quick start

```powershell
cd frontend
flutter pub get
flutter run -d windows
```

Read these before development:

1. `docs/TEAM_HANDOFF.md`
2. `docs/ARCHITECTURE.md`
3. `docs/API_CONTRACT.md`
4. `docs/SECURITY.md`
5. `docs/ROADMAP.md`
