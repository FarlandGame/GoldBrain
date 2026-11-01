# GoldBrain — Three Phase Build

## Phase 1 — Foundation & Handoff ✅

- Reorganize repository into frontend/backend/docs.
- Add FastAPI backend foundation.
- Add SQLite-zero-config + PostgreSQL/Docker path.
- Add market-provider gateway and canonical assets.
- Add forecast audit database contract.
- Add Flutter backend client without breaking old services.
- Add security boundary for private alpha.
- Add automated backend tests and developer docs.

**Exit gate:** both developers can work independently; backend starts locally; API tests pass.

## Phase 2 — Intelligence Private Alpha ✅

- Persist normalized OHLC/quote history server-side.
- Add server-side market history and news/AI replacements; keep legacy Flutter paths during staged UI migration.
- Build feature pipeline and baseline backtester.
- Build Forecast V2 as champion/challenger models rather than one opaque model.
- Calibrate confidence and forecast intervals.
- Add immutable evaluation ledger and performance dashboard APIs.
- Add deep-analysis endpoint using structured evidence/events.
- Add paper-trading engine and journal (no real-money automation).

**Exit gate:** private alpha can prove forecast quality out-of-sample and cannot hide failed predictions.

## Phase 3 — Product-Ready Private Beta ✅

- Real user/session architecture and secure secret storage.
- Device/session management, rate limits, audit logs and 2FA-ready flows.
- Portfolio + paper-trading backend/client foundation; visible Flutter UI remains a frontend follow-up.
- Alerts/notification backend.
- Deployment hardening, backups, monitoring and CI quality gates.
- Subscription/entitlement interfaces prepared but disabled until public launch decisions.
- Exchange adapter interface + sandbox/mock connector; real-money execution remains gated behind
  security, legal, risk and paper-performance review.

**Exit gate:** clean handoff-ready codebase for continued development and a controlled private beta.
