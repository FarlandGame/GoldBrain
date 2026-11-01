# Private-beta frontend validation

Validated on Windows on 2026-09-08 against backend commit `08ad208`.

| Check | Result |
| --- | --- |
| Flutter analyzer | No issues |
| Complete Flutter suite, including screenshot capture | 296 passed, 10 skipped |
| New private-beta widget suite after screenshot font correction | 4 passed |
| Flutter HTTP client against real FastAPI and disposable SQLite | 1 passed |
| Backend pytest suite with provider credentials blank | 27 passed, one upstream deprecation warning |
| Windows release build | Successful |
| Start/stop scripts | PowerShell parse successful; fresh SQLite migrations through 0005, readiness and worker startup verified |

The complete suite skips nine existing optional/prototype tests and the opt-in
real-server test; that real-server test was run separately with its flag enabled.
Screenshots are explicitly labelled test data and were visually inspected at
1440x1000. Narrow RTL navigation was tested at 390x844.

New regression coverage includes concurrent 401 refresh rotation, 204 logout,
storage failure, logout during an in-flight secure write, offline restoration,
metric scales, invalid bounds/probabilities, future/mixed-provider history,
forecast anchor currency verification, IRR/IRT conversion without USD/USDT parity
assumptions, read-only dashboard polling, conditional horizons, paper-only signal
gates, and gold-context unit mismatch.

The real-server test covers registration, identity, quotes/overview/gold context,
history, persisted forecasts and latest retrieval at 1h and 15m (1m candles),
metrics, news, deep analysis, alerts, paper buy/sell and fees, refresh rotation,
sessions, reset request and logout. Providers are synthetic and the database is
temporary; no real orders are submitted and no profitability claim is tested.

The native secure-storage plugin compiles into the Windows release. Its OS
credential persistence should also be exercised during the user's manual
close/reopen test; unit/widget tests inject an in-memory vault.

Backend schemas/migrations are unchanged relative to the merged teammate branch.
The launcher backs up the existing default SQLite file before running teammate
migrations. Custom databases require their own backup procedure.

## UI evidence (synthetic test data)

![Dashboard with test data](screenshots/private-beta/dashboard-test-data.png)

![Shared asset details with test data](screenshots/private-beta/asset-test-data.png)

See `FRONTEND_PRIVATE_BETA_FA.md` for the manual test path and
`FRONTEND_API_GAPS.md` for remaining server dependencies. Live provider reliability,
production email delivery, global risk limits and automatic trading are outside
what these passing client tests establish.
