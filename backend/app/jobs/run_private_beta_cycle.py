from __future__ import annotations

import asyncio
import json

from app.core.config import get_settings
from app.db.session import SessionLocal
from app.services.forecasting import ForecastError, ForecastService
from app.services.history import MarketHistoryService
from app.services.market_collector import MarketCollector
from app.services.market_data import MarketDataService
from app.services.observability import MarketObservabilityService


async def run_once() -> dict[str, object]:
    settings = get_settings()
    market_data = MarketDataService(settings)
    db = SessionLocal()
    try:
        collection = await MarketCollector(market_data).collect_once(db)
        telemetry = market_data.drain_observability()
        telemetry_service = MarketObservabilityService()
        for item in telemetry:
            telemetry_service.record(
                db,
                provider=str(item.get("provider", "unknown")),
                operation=str(item.get("operation", "quotes")),
                status=str(item.get("status", "error")),
                latency_ms=(
                    int(str(item["latency_ms"]))
                    if isinstance(item.get("latency_ms"), (int, float, str))
                    else None
                ),
                error_kind=str(item["error_kind"]) if item.get("error_kind") else None,
                fallback_used=bool(item.get("fallback_used")),
            )
        hourly_candles = {
            symbol: MarketHistoryService().build_quote_candles(
                db,
                symbol=symbol,
                timeframe="1h",
                lookback_hours=72,
            )
            for symbol in collection.requested_symbols
            if symbol in {"GOLD18", "USDT", "BTC", "XAU"}
        }
        forecasts: dict[str, dict[str, object]] = {}
        for symbol in ("BTC", "USDT", "GOLD18"):
            try:
                forecast = ForecastService().generate(
                    db, symbol=symbol, horizon="1h", timeframe="1h", persist=True
                )
                forecasts[symbol] = {
                    "forecast_id": forecast.forecast_id,
                    "signal": forecast.signal,
                    "signal_quality": forecast.signal_quality,
                    "trade_allowed": forecast.trade_allowed,
                }
            except ForecastError as exc:
                forecasts[symbol] = {"status": "unavailable", "reason": str(exc)}
        evaluated, expired, pending = ForecastService().evaluate_due(db)
        return {
            "collected_quotes": collection.collected_quotes,
            "quote_issues": collection.quote_issues,
            "hourly_candles": {
                symbol: {
                    "inserted": result.inserted,
                    "updated": result.updated,
                    "rejected": result.rejected,
                }
                for symbol, result in hourly_candles.items()
            },
            "forecasts": forecasts,
            "evaluation": {"evaluated": evaluated, "expired": expired, "pending": pending},
        }
    finally:
        db.close()
        await market_data.close()


async def main() -> None:
    print(json.dumps(await run_once(), ensure_ascii=False))


if __name__ == "__main__":
    asyncio.run(main())
