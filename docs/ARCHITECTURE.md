# GoldBrain Architecture

## Target shape

```text
Flutter (frontend)
        |
        | HTTPS / JSON
        v
FastAPI (backend)
  |        |        |
  v        v        v
Market   Intelligence  Auth/Risk
Gateway  + Forecast    (later)
  |
  v
PostgreSQL / provider APIs
```

## Core rules

1. Flutter is a presentation client. New provider secrets must not be added to it.
2. Backend owns external market-provider calls and later AI/model calls.
3. Every future forecast must be immutable/auditable: generated time, target time,
   model version, bounds and confidence are stored before the outcome is known.
4. Provider failures fail closed. Missing values are never invented.
5. Live trading is not part of the foundation. Paper trading and risk gates come first.

## Repository ownership

- `frontend/`: Flutter/UI — primarily frontend owner.
- `backend/`: FastAPI/data/backend — primarily backend owner.
- `docs/`: shared API contracts, architecture, decisions.
- Root infra files (`docker-compose.yml`, CI): shared ownership.

Cross-cutting changes should be documented before changing both frontend and backend in one PR.


## Private-beta security boundary

```text
Flutter -> HTTPS -> FastAPI -> Auth/Entitlement -> Market/Forecast/Intelligence
                              -> User-scoped Paper Trading
                              -> PostgreSQL
```

Real exchange order execution is outside the current trust boundary and remains disabled.
