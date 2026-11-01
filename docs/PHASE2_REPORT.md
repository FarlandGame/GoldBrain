# Phase 2 Report — Intelligence Private Alpha

## What changed

- Added normalized OHLCV storage (`market_candles`).
- Live quote responses are persisted server-side and can be aggregated into honest OHLC candles.
- Added leak-aware feature engine (returns, momentum, EMA spread, RSI, ATR, volatility).
- Added Forecast V2:
  - robust statistical baseline,
  - scikit-learn HistGradientBoosting challenger,
  - challenger weight selected from chronological validation error,
  - forecast interval + provisional/validation-based probability,
  - immutable forecast audit records.
- Added evaluation ledger and independent-sample metrics (MAE, MAPE, direction hit rate,
  interval coverage, Brier score).
- Added chronological 70/15/15 train/calibration/test backtest endpoint.
- Moved financial RSS fetching into the backend and persist articles.
- Added Deep Analysis endpoint. Numerical forecasts come only from the forecasting engine;
  the optional LLM may explain supplied evidence but may not invent numbers.
- Added long-only spot Paper Trading accounts, positions and journal.
- Extended Flutter backend client with Forecast, Backtest, Deep Analysis and Paper Trading calls.

## Important private-alpha rule

A displayed confidence number is not a guarantee. Until at least 30 independent evaluated
forecasts exist for a symbol/horizon, calibration remains provisional.

## Phase 2 API surface

- `GET /api/v1/history/candles`
- `POST /api/v1/history/candles`
- `POST /api/v1/history/aggregate-quotes`
- `POST /api/v1/forecast`
- `POST /api/v1/forecast/evaluate`
- `GET /api/v1/forecast/metrics`
- `POST /api/v1/forecast/backtest`
- `GET /api/v1/intelligence/news`
- `POST /api/v1/intelligence/deep-analysis`
- `POST /api/v1/paper/accounts`
- `POST /api/v1/paper/orders`
- `GET /api/v1/paper/portfolio/{account_key}`

## Exit gate

Phase 2 is complete when all backend tests pass and private-alpha forecasts can be generated,
stored, backtested and later evaluated without deleting failed predictions.
