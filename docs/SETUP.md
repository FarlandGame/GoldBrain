# Fresh-clone setup

## Toolchain

The preserved frontend requires Dart `^3.12.2`; inspection used Flutter 3.44.6 / Dart 3.12.2. Backend metadata requires Python >=3.11, while original CI/Docker target Python 3.12. Use Python 3.12 as the first reproduction target. A newer SDK is not assumed compatible merely because it exists. See checked-in manifests for exact dependency versions/ranges.

No private configuration or account database is shipped. Create your own `.env` and database. No signup, email, provider completion or real account is needed to run the ordinary mocked unit tests.

## Backend: local SQLite development

From repository root, in PowerShell:

```powershell
cd backend
py -3.12 -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install -r requirements-dev.txt
New-Item -ItemType Directory -Force data
Copy-Item .env.example .env
```

Edit your **local** `backend/.env`: for SQLite set `GOLDBRAIN_DATABASE_URL=sqlite:///./data/goldbrain.db`. Generate your own random `GOLDBRAIN_JWT_SECRET` and `GOLDBRAIN_PRIVATE_API_KEY`. The example's PostgreSQL username/password are explicitly local development placeholders. Keep `.env` ignored. Generate a different random value for each secret; for example, run `python -c "import secrets; print(secrets.token_urlsafe(48))"` separately for each value.

```powershell
alembic upgrade head
pytest -q
uvicorn app.main:app --host 127.0.0.1 --port 8000 --reload
```

The development API docs are at `http://127.0.0.1:8000/docs`. Health/readiness endpoints are in the source API contract. Missing external credentials/data may produce explicit unavailable states rather than usable AI/news/market output. Email verification/reset requires your independently configured SMTP sender; no working sender is bundled.

For the original PostgreSQL17 development path, inspect `docker-compose.yml` and change its development-only credentials/configuration for your environment. A fresh PostgreSQL E2E deployment is not part of this archive's verification report.

## Frontend

In a separate terminal:

```powershell
cd frontend
flutter pub get
flutter analyze
flutter test
flutter run -d windows
```

Windows desktop development also requires the native Windows build tooling expected by Flutter. The default backend transport targets the local API; review `frontend/lib/core/backend_api_client.dart` and `backend_connection.dart` before changing endpoints. The integrated app includes Windows/web scaffolds; current Android/web builds are not certified by this publication.

## Optional original audio

Download `GoldBrain-audio-assets.zip` from [the preserved-source release](https://github.com/FarlandGame/GoldBrain/releases/tag/preserved-2026-11-01). From repository root:

```powershell
python scripts/restore_audio.py --archive "C:\path\to\GoldBrain-audio-assets.zip"
```

The script checks the exact expected audio paths and hashes before writing them. It does not download anything. Source builds can omit the pack; bundled playback and opt-in native audio smoke tests then cannot be expected to work. Do not mistake the ordinary unit test result for an audio playback test.

## Market collection is separate from opening the UI

After independent provider setup and migrations, the existing jobs can backfill history and run a supervised private-beta collection cycle. Read `backend/README.md` and the job code first. The preserved `Start-GoldBrain.ps1` automatically starts a collection worker and may fetch dependencies/create a venv. `Stop-GoldBrain.ps1` has broad process-matching behavior. Prefer the explicit two-terminal workflow above for the first reproduction; these launchers are preserved source, not newly verified production supervision.
