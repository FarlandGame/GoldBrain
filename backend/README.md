# GoldBrain Backend — Private Beta Foundation

Python/FastAPI backend for market data, forecasting, research backtesting, news intelligence,
paper trading and user/session security.

## Stack

- FastAPI + Pydantic
- SQLAlchemy + Alembic
- PostgreSQL in Docker / SQLite for zero-config local development
- NumPy + scikit-learn (baseline + ML challenger forecasting)
- Argon2id passwords + JWT access tokens + rotated refresh tokens
- httpx for external provider calls

## Run

### PostgreSQL (recommended)

From the repository root:

```powershell
Copy-Item backend/.env.example backend/.env
# Set NAVASAN_API_KEY and a random GOLDBRAIN_JWT_SECRET in backend/.env.
docker compose up --build
```

The backend container waits for PostgreSQL and runs `alembic upgrade head`
before starting Uvicorn. Verify `http://127.0.0.1:8000/api/v1/ready`.

### Local development without Docker

```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements-dev.txt
Copy-Item .env.example .env
alembic upgrade head
pytest -q
uvicorn app.main:app --reload
```

For a local SQLite-only run, set
`GOLDBRAIN_DATABASE_URL=sqlite:///./data/goldbrain.db` and
`GOLDBRAIN_AUTO_CREATE_TABLES=false`, then run `alembic upgrade head` before
starting Uvicorn. Do not use `AUTO_CREATE_TABLES=true` outside development or
tests.

Do not put market-provider, AI or future exchange credentials in Flutter. Secrets belong in backend environment variables.

Real-money order execution is not implemented. `/exchange/capabilities` intentionally reports it disabled.

## Private-beta market collection

Run a single collection for `GOLD18`, `USDT` and `BTC` with:

```powershell
python -m app.jobs.collect_market_data
```

Schedule this command outside the API process (for example, Windows Task
Scheduler during development). The collector records only successfully
validated, fresh quotes and derives honest 1-minute candles from stored quote
observations.

Backfill BTC or USDT candle history from Wallex before training or backtesting:

```powershell
python -m app.jobs.backfill_wallex_history --symbol BTC --timeframe 1h --lookback-hours 720
python -m app.jobs.backfill_wallex_history --symbol USDT --timeframe 1h --lookback-hours 720
```

This job is intentionally limited to public Wallex markets. It does not invent
Gold18 history; that history starts with verified collected quotes unless a
licensed provider is added.

Evaluate due forecasts after their target time, so dashboard metrics are based
on recorded outcomes rather than claims:

```powershell
python -m app.jobs.evaluate_forecasts
```

Run the complete private-beta cycle (collect, generate auditable forecasts and
evaluate due outcomes) with:

```powershell
python -m app.jobs.run_private_beta_cycle
```

It never places exchange orders. Forecasts with unchanged candle evidence reuse
their immutable ledger record rather than creating duplicates.
