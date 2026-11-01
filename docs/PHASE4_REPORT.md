# Phase 4 — Market Data Infrastructure + Forecast Validation

Date: 2026-09-12  
Branch: `backend/phase4-market-data-validation`

## Provider audit and decision

| Asset | Previous source | Observed problem | Phase 4 chain | Data contract |
|---|---|---|---|---|
| BTC | Wallex `/v1/markets`; Wallex UDF history; Nobitex fallback | Snapshot has no per-ticker source timestamp, so receipt time could be mistaken for market time; fallback was implicit | Wallex primary, Nobitex/ZARIX/Gold API fallback; Wallex is the only automatic historical source | coin, USDT, GLOBAL |
| USDT | Wallex `USDTTMN`; Nobitex `usdt-rls`; Navasan/ZARIX fallback | Rial-to-toman conversion and provider market identity were not persisted; provider errors were only returned as a generic issue | Wallex primary, Nobitex secondary, Navasan/ZARIX fallback | coin, IRT, IRAN |
| GOLD18 | Navasan when key configured; ZARIX/PersianToolbox fallback | A generic per-gram reference did not prove 18K tradable Iranian-market price; historical source was not approved | Navasan preferred; ZARIX/PersianToolbox visible reference fallback; no historical backfill until licensed source approval | gram_18k, IRT, IRAN |

Wallex's official API reference documents the public markets and UDF OHLC history endpoints ([API reference](https://api-docs.wallex.ir/), [developer introduction](https://developers.wallex.ir/intro)). Nobitex's official documentation documents market stats, UDF history, a 20 requests/minute market-stats limit and public candle streaming ([market API](https://apidocs.nobitex.ir/)). Navasan remains the key-based Iranian reference provider ([web-service guide](https://www.navasan.tech/webserviceguide/)). The implementation keeps the existing providers because they cover the required Iranian symbols and preserve the current private-beta contract; no unverified “free” API was promoted to the primary Gold18 source.

## Architecture and freshness

`MarketQuote` and `MarketCandle` now carry source, unit, market, provider timestamp, server receipt time, latency, freshness status, quality status and flags. A missing upstream timestamp is represented as `null`, never fabricated. Freshness is classified as `LIVE`, `FRESH`, `DELAYED`, `STALE` or `UNAVAILABLE`; future timestamps, non-positive/non-finite prices and currency/unit mismatches are rejected.

The worker still polls every 60 seconds (the configured interval). Navasan's configured cadence is provider-dependent; its timestamp is used when present. Wallex/Nobitex snapshots are receipt-time observations and are marked with `provider_timestamp_unavailable`. Transport latency is measured separately from source-data age. The API refuses stale cache entries and status responses expose age and last successful update.

Fallback is explicit in `fallback_from`, `quality_flags` and provider telemetry. There is no averaging across providers. `cross_provider_check()` compares an optional independent quote, records spread and flags a spread above 2%; it returns the primary value unchanged.

Raw quotes are stored before quote-derived candles. Fingerprints prevent duplicate ticks. Candle identity is `(symbol, timeframe, provider, opened_at)` plus a content fingerprint; duplicate or revised candles are rejected and never overwritten. Quote-derived candles preserve source tick IDs and aggregate only one coherent provider/currency/unit/market series. Missing intervals remain gaps and are counted; no interpolation is performed.

## Forecast validation

Forecast rows now have a deterministic unique input key and immutable evidence manifest (candle IDs, providers, currencies, units, source timestamps and model version). Concurrent/repeated generation reuses the existing row. An ORM guard rejects changes to prediction inputs and outcomes after insertion while retaining the legacy explanation backfill path.

Evaluation is exactly once through the unique `forecast_id` constraint and an insert/rollback race-safe path. It selects a valid completed candle at or after the target, from the same provider/currency/unit evidence series. Stale, unverified, invalid or non-positive target prices remain pending/expired and are not forced into metrics. Metrics now include RMSE, average confidence, strong-signal accuracy and baseline directional rate in addition to existing MAE/MAPE/directional/interval/Brier values.

## Migrations

- `0006_market_data_quality`: provenance, quality, freshness, fingerprint and candle completeness fields.
- `0007_forecast_validation`: immutable forecast input key/evidence manifest and immutable actual-evidence fields.
- `0008_market_observability`: sanitized provider telemetry table.

## Changed files

Backend models/schemas/services were extended in `app/core/market_quality.py`,
`app/services/provider_registry.py`, `app/services/history.py`,
`app/services/market_data.py`, `app/services/market_status.py`,
`app/services/observability.py`, `app/services/forecasting.py`, the market and
history routes, and the worker cycle. New model `MarketProviderMetricRecord`
and the three migrations were added. `docs/API_CONTRACT.md` documents the
contract and `/market/observability` endpoint. The Flutter UI was not redesigned.

## Tests

Added `tests/test_phase4_market_data.py` for provider down, timeout, rate limit,
invalid/stale/future prices, duplicate candles, out-of-order history, fallback
provenance, historical gaps, currency/unit mismatch, immutable forecasts,
exactly-once evaluation and invalid target evidence. Full Backend suite:

```
36 passed, 1 warning
```

The warning is the existing Starlette/AnyIO deprecation warning. Alembic
`upgrade head` completed through `0008_market_observability`. Frontend code was
not changed in this phase; its previously verified Flutter suite remains
`291 passed, 9 skipped`.

## Remaining risks and go/no-go

Gold18 still lacks an approved licensed historical provider. Wallex and Nobitex
live snapshots do not expose per-ticker source timestamps, so their source age is
unknown beyond the server observation age. Cross-provider comparison is opt-in to avoid violating
provider limits. Provider metrics are persisted only when the API or worker
flushes the service telemetry buffer; a hard process crash between request and
flush loses that small in-memory interval.

Market data is reliable enough to begin **controlled raw collection and
paper-only validation for BTC/USDT**. It is **not** sufficient to start real
money trading, and GOLD18 forecasts must remain `No Trade` until an approved
18K Iranian source and historical coverage pass the same checks. Phase 5 is
intentionally not started.
