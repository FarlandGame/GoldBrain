# Development Guide

## Backend owner

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

For PostgreSQL:

```powershell
docker compose up -d postgres
```

Then use:

```text
GOLDBRAIN_DATABASE_URL=postgresql+psycopg://goldbrain:goldbrain_dev_only@127.0.0.1:5432/goldbrain
```

Run the complete repository check from root:

```powershell
python scripts/check_final.py
```

## Frontend owner

```powershell
cd frontend
flutter pub get
flutter test
flutter run -d windows
```

Local backend routing:

```powershell
[Environment]::SetEnvironmentVariable('GOLDBRAIN_API_BASE_URL', 'http://127.0.0.1:8000', 'User')
```

During early local development the owner API key can still be used. The preferred private-beta flow is backend `/auth/*` + Bearer access tokens. `GoldBrainBackendClient` now supports both.

Do not persist a refresh token in plain SharedPreferences for a public build. Add OS-backed secure storage before external beta users.

## Database changes

Never edit a production schema manually. Change SQLAlchemy models and create an Alembic migration.

```powershell
cd backend
alembic revision --autogenerate -m "describe change"
alembic upgrade head
```

## Team rule

Prefer small PRs. Any JSON contract change must update `docs/API_CONTRACT.md` and the corresponding Flutter parser/client in the same PR.
