# GoldBrain — Two-Person Handoff

## Ownership

### Backend / AI owner

Work primarily in:

- `backend/app/services/`
- `backend/app/models/`
- `backend/app/api/`
- `backend/tests/`
- Alembic migrations

Main responsibilities: data quality, forecast research, backtesting, API security, persistence and provider integrations.

### Flutter / Frontend owner

Work primarily in:

- `frontend/lib/screens/`
- `frontend/lib/widgets/`
- `frontend/lib/core/backend_api_client.dart`

Main responsibilities: UX, charts, auth flow, prediction presentation, paper portfolio/journal, alerts and error states.

## Branch rule

Use feature branches and small PRs. If JSON changes, backend schema + API contract + Flutter parser should change together.

Suggested branches:

- `backend/<feature>`
- `frontend/<feature>`
- `shared/<contract-change>`

## Immediate next development tasks

Backend:

1. Add licensed historical data providers and scheduled collectors.
2. Add model registry / experiment tracking.
3. Expand feature sets per asset class.
4. Build independent forecast calibration datasets.
5. Add a background worker/Redis before production alerts.

Frontend:

1. Move login/register UI from legacy local/Supabase flow to GoldBrain backend auth.
2. Store refresh tokens using an OS-backed secure storage solution before public beta.
3. Replace legacy local forecast cards with `/forecast` + `/metrics`.
4. Build Paper Trading screens against `/paper/*`.
5. Build session/device and alerts screens.

Shared:

1. Decide exact private-beta assets/timeframes.
2. Define minimum evidence threshold before showing a confidence percentage.
3. Define branding/legal/risk copy before inviting external users.
