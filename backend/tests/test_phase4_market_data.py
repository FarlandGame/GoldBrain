import math
from datetime import datetime, timedelta, timezone

import httpx
import pytest
from sqlalchemy import create_engine, select
from sqlalchemy.orm import Session

from app.db.base import Base
from app.models.forecast import ForecastEvaluationRecord, ForecastRecord
from app.services.observability import MarketObservabilityService
from app.schemas.history import MarketCandle
from app.schemas.market import MarketQuote
from app.services.history import MarketHistoryService
from app.services.market_data import MarketDataService
from app.services.forecasting import ForecastService


def _db() -> Session:
    engine = create_engine("sqlite://")
    Base.metadata.create_all(engine)
    return Session(engine)


def _quote(**kwargs) -> MarketQuote:
    now = datetime.now(timezone.utc)
    return MarketQuote(
        symbol=kwargs.get("symbol", "BTC"), name="BTC", currency=kwargs.get("currency", "USDT"),
        price=kwargs.get("price", 100), updated_at=kwargs.get("updated_at", now), provider="fixture",
        unit=kwargs.get("unit", "coin"), market=kwargs.get("market", "GLOBAL"),
        provider_timestamp=kwargs.get("provider_timestamp"),
    )


def _candle(opened: datetime, **kwargs) -> MarketCandle:
    return MarketCandle(
        symbol=kwargs.get("symbol", "BTC"), timeframe="1h", currency=kwargs.get("currency", "USDT"),
        provider=kwargs.get("provider", "fixture"), opened_at=opened, closed_at=opened + timedelta(hours=1),
        open=100, high=102, low=99, close=101, volume=1,
        unit=kwargs.get("unit", "coin"), market=kwargs.get("market", "GLOBAL"),
    )


def _forecast_candles(count: int = 80) -> list[MarketCandle]:
    start = datetime(2026, 1, 1, tzinfo=timezone.utc)
    price = 100.0
    candles: list[MarketCandle] = []
    for index in range(count):
        close = price * (1 + 0.001 + math.sin(index / 8) * 0.001)
        opened = start + timedelta(hours=index)
        candles.append(
            MarketCandle(
                symbol="BTC",
                timeframe="1h",
                currency="USDT",
                provider="fixture",
                opened_at=opened,
                closed_at=opened + timedelta(hours=1),
                open=price,
                high=max(price, close) * 1.001,
                low=min(price, close) * 0.999,
                close=close,
                volume=1000 + index,
            )
        )
        price = close
    return candles


@pytest.mark.asyncio
async def test_provider_down_timeout_and_rate_limit_fail_closed() -> None:
    def handler(request: httpx.Request) -> httpx.Response:
        if request.url.host == "api.wallex.ir":
            if request.url.path.endswith("markets"):
                raise httpx.ReadTimeout("timeout")
            return httpx.Response(429, json={})
        return httpx.Response(503, json={})

    client = httpx.AsyncClient(transport=httpx.MockTransport(handler))
    service = MarketDataService(__import__("app.core.config", fromlist=["Settings"]).Settings(environment="test", auto_create_tables=False, navasan_api_key="", market_cache_seconds=0), client=client)
    try:
        result = await service.fetch_quotes(["BTC"])
    finally:
        await client.aclose()
    assert "BTC" in result.issues
    assert all(item.get("status") in {"error", "success"} for item in service.observability_snapshot())


def test_invalid_stale_and_future_quotes_rejected() -> None:
    db = _db()
    history = MarketHistoryService()
    assert history.persist_quotes(
        db,
        [
            _quote(price=0),
            _quote(price=float("nan")),
            _quote(updated_at=datetime(2020, 1, 1, tzinfo=timezone.utc)),
            _quote(provider_timestamp=datetime.now(timezone.utc) + timedelta(hours=1)),
        ],
    ) == 1
    row = db.scalar(select(__import__("app.models.market", fromlist=["MarketQuoteRecord"]).MarketQuoteRecord))
    assert row.freshness_status in {"STALE", "DELAYED"}
    db.close()


def test_duplicate_candle_and_out_of_order_history_are_safe() -> None:
    db = _db()
    history = MarketHistoryService()
    start = datetime(2026, 1, 1, tzinfo=timezone.utc)
    first = _candle(start)
    assert history.upsert_candles(db, [first]).inserted == 1
    duplicate = history.upsert_candles(db, [first])
    assert duplicate.rejected == 1
    # A candle from the past is accepted as historical data, but reads remain chronological.
    assert history.upsert_candles(db, [_candle(start - timedelta(hours=1))]).inserted == 1
    rows = history.get_candles(db, "BTC", "1h", closed_before=start + timedelta(hours=3))
    assert [row.opened_at for row in rows] == sorted(row.opened_at for row in rows)
    db.close()


def test_currency_unit_mismatch_rejected() -> None:
    db = _db()
    history = MarketHistoryService()
    start = datetime(2026, 1, 1, tzinfo=timezone.utc)
    assert history.upsert_candles(db, [_candle(start, currency="IRT")]).rejected == 1
    assert history.persist_quotes(db, [_quote(currency="IRT")]) == 0
    db.close()


def test_fallback_provider_is_explicit() -> None:
    def handler(request: httpx.Request) -> httpx.Response:
        if request.url.host == "api.wallex.ir":
            return httpx.Response(503, json={})
        if request.url.host == "api.nobitex.ir":
            return httpx.Response(200, json={"status": "ok", "stats": {"btc-usdt": {"latest": "65000"}}})
        return httpx.Response(404, json={})

    client = httpx.AsyncClient(transport=httpx.MockTransport(handler))
    settings = __import__("app.core.config", fromlist=["Settings"]).Settings(environment="test", auto_create_tables=False, navasan_api_key="", market_cache_seconds=0)
    import asyncio
    result = asyncio.run(MarketDataService(settings, client=client).fetch_quotes(["BTC"]))
    asyncio.run(client.aclose())
    assert result.quotes["BTC"].fallback_from == "wallex"


def test_historical_gap_count_is_reported() -> None:
    db = _db()
    history = MarketHistoryService()
    start = datetime(2026, 1, 1, tzinfo=timezone.utc)
    history.upsert_candles(db, [_candle(start), _candle(start + timedelta(hours=2))])
    rows = history.get_candles(db, "BTC", "1h", closed_before=start + timedelta(hours=4))
    assert history.gap_count(rows, "1h") == 1
    db.close()


def test_forecast_is_immutable_and_evaluation_is_exactly_once() -> None:
    db = _db()
    history = MarketHistoryService()
    history.upsert_candles(db, _forecast_candles())
    service = ForecastService(history)
    generated_at = datetime(2026, 1, 4, 7, tzinfo=timezone.utc)

    first = service.generate(db, symbol="BTC", horizon="1h", timeframe="1h", now=generated_at)
    second = service.generate(db, symbol="BTC", horizon="1h", timeframe="1h", now=generated_at)
    assert second.forecast_id == first.forecast_id
    assert len(list(db.scalars(select(ForecastRecord)))) == 1

    row = db.scalar(select(ForecastRecord))
    assert row is not None
    row.point_estimate += 1
    with pytest.raises(ValueError, match="immutable"):
        db.commit()
    db.rollback()

    first_eval = service.evaluate_due(db, now=generated_at + timedelta(hours=1))
    second_eval = service.evaluate_due(db, now=generated_at + timedelta(hours=1))
    assert first_eval[0] == 1
    assert second_eval[0] == 0
    assert len(list(db.scalars(select(ForecastEvaluationRecord)))) == 1
    db.close()


def test_invalid_target_evidence_is_not_forced_into_evaluation() -> None:
    db = _db()
    history = MarketHistoryService()
    candles = _forecast_candles()
    candles[-1] = candles[-1].model_copy(update={"data_quality_status": "UNVERIFIED"})
    history.upsert_candles(db, candles)
    service = ForecastService(history)
    generated_at = datetime(2026, 1, 4, 7, tzinfo=timezone.utc)

    service.generate(db, symbol="BTC", horizon="1h", timeframe="1h", now=generated_at)
    result = service.evaluate_due(db, now=generated_at + timedelta(hours=1))
    assert result == (0, 0, 1)
    assert len(list(db.scalars(select(ForecastEvaluationRecord)))) == 0
    db.close()


def test_observability_counts_fallback_requests_without_quote_provenance() -> None:
    db = _db()
    service = MarketObservabilityService()
    service.record(
        db,
        provider="persian-toolbox",
        operation="quotes",
        status="success",
        latency_ms=12,
        fallback_used=True,
    )
    snapshot = service.market_snapshot(db)
    assert snapshot["fallback_usage"] == 1
    db.close()
