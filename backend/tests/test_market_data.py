from datetime import datetime, timedelta, timezone

import httpx
import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import Session
from sqlalchemy.pool import StaticPool

from app.core.config import Settings
from app.db.base import Base
from app.models.candle import MarketCandleRecord
from app.models.market import MarketQuoteRecord
from app.schemas.history import MarketCandle
from app.services.history import MarketHistoryService
from app.services.market_data import MarketDataService
from app.services.market_overview import MarketOverviewService
from app.services.market_status import MarketStatusService
from app.services.observability import MarketObservabilityService


@pytest.mark.asyncio
async def test_gold_api_fallback_returns_valid_quote() -> None:
    def handler(request: httpx.Request) -> httpx.Response:
        if request.url.host == "zarix.online":
            return httpx.Response(503, json={"ok": False})
        if request.url.host == "api.gold-api.com" and request.url.path.endswith("/price/XAU"):
            return httpx.Response(
                200,
                json={
                    "symbol": "XAU",
                    "name": "Gold",
                    "currency": "USD",
                    "price": 3600.5,
                    "updatedAt": datetime.now(timezone.utc).isoformat(),
                },
            )
        return httpx.Response(404, json={})

    client = httpx.AsyncClient(transport=httpx.MockTransport(handler))
    settings = Settings(environment="test", auto_create_tables=False, market_cache_seconds=0)
    service = MarketDataService(settings, client=client)
    try:
        result = await service.fetch_quotes(["XAU"])
    finally:
        await client.aclose()
    assert result.quotes["XAU"].price == 3600.5
    assert result.quotes["XAU"].provider == "gold-api"


@pytest.mark.asyncio
async def test_zarix_global_reference_remains_unverified_even_with_source_time() -> None:
    source_time = datetime.now(timezone.utc).isoformat()

    def handler(request: httpx.Request) -> httpx.Response:
        assert request.url.host == "zarix.online"
        return httpx.Response(200, json={"ok": True, "data": {"items": [{
            "symbol": "XAUUSD", "price": 3600, "unit": "USD / ounce",
            "sourceTime": source_time,
        }]}})

    client = httpx.AsyncClient(transport=httpx.MockTransport(handler))
    service = MarketDataService(Settings(environment="test", auto_create_tables=False), client=client)
    try:
        quote = (await service.fetch_quotes(["XAU"])).quotes["XAU"]
    finally:
        await client.aclose()
    assert quote.provider == "zarix"
    assert quote.provider_timestamp is not None
    assert quote.data_quality_status == "UNVERIFIED"
    assert "provider_unverified" in quote.quality_flags


@pytest.mark.asyncio
async def test_unsupported_symbol_fails_closed() -> None:
    client = httpx.AsyncClient(transport=httpx.MockTransport(lambda _: httpx.Response(500)))
    settings = Settings(environment="test", auto_create_tables=False)
    service = MarketDataService(settings, client=client)
    try:
        result = await service.fetch_quotes(["NOTREAL"])
    finally:
        await client.aclose()
    assert not result.quotes
    assert "NOTREAL" in result.issues


@pytest.mark.asyncio
async def test_wallex_is_primary_for_bitcoin_and_tether() -> None:
    def handler(request: httpx.Request) -> httpx.Response:
        assert request.url.host == "api.wallex.ir"
        assert request.url.path == "/v1/markets"
        return httpx.Response(
            200,
            json={
                "result": {
                    "symbols": {
                        "BTCUSDT": {
                            "faBaseAsset": "بیت کوین",
                            "stats": {"lastPrice": "65000", "24h_ch": 1.2},
                        },
                        "USDTTMN": {"faBaseAsset": "تتر", "stats": {"lastPrice": "90000", "24h_ch": -0.1}},
                    }
                }
            },
        )

    client = httpx.AsyncClient(transport=httpx.MockTransport(handler))
    settings = Settings(environment="test", auto_create_tables=False, market_cache_seconds=0)
    service = MarketDataService(settings, client=client)
    try:
        result = await service.fetch_quotes(["BTC", "USDT"])
    finally:
        await client.aclose()

    assert result.issues == {}
    assert result.quotes["BTC"].price == 65000
    assert result.quotes["BTC"].currency == "USDT"
    assert result.quotes["USDT"].price == 90000
    assert result.quotes["USDT"].currency == "IRT"
    assert all(quote.provider == "wallex" for quote in result.quotes.values())


@pytest.mark.asyncio
async def test_nobitex_fallback_converts_rial_tether_price_to_toman() -> None:
    def handler(request: httpx.Request) -> httpx.Response:
        if request.url.host == "api.wallex.ir":
            return httpx.Response(503, json={})
        assert request.url.host == "api.nobitex.ir"
        return httpx.Response(
            200,
            json={
                "status": "ok",
                "stats": {"usdt-rls": {"latest": "901230", "dayChange": "0.5"}},
            },
        )

    client = httpx.AsyncClient(transport=httpx.MockTransport(handler))
    settings = Settings(environment="test", auto_create_tables=False, market_cache_seconds=0)
    service = MarketDataService(settings, client=client)
    try:
        result = await service.fetch_quotes(["USDT"])
    finally:
        await client.aclose()

    assert result.issues == {}
    assert result.quotes["USDT"].price == 90123
    assert result.quotes["USDT"].provider == "nobitex"


@pytest.mark.asyncio
async def test_unverified_gold18_references_are_not_requested() -> None:
    called: list[str] = []
    def handler(request: httpx.Request) -> httpx.Response:
        called.append(str(request.url))
        return httpx.Response(200, json={"ok": True, "data": {"items": []}})

    client = httpx.AsyncClient(transport=httpx.MockTransport(handler))
    settings = Settings(environment="test", auto_create_tables=False, market_cache_seconds=0)
    service = MarketDataService(settings, client=client)
    try:
        result = await service.fetch_quotes(["GOLD18"])
    finally:
        await client.aclose()

    assert "GOLD18" in result.issues
    assert "GOLD18" not in result.quotes
    assert called == []


@pytest.mark.asyncio
async def test_unverified_zarix_domestic_fx_is_not_requested() -> None:
    called: list[str] = []
    def handler(request: httpx.Request) -> httpx.Response:
        called.append(str(request.url))
        return httpx.Response(200, json={"ok": True, "data": {"items": []}})

    client = httpx.AsyncClient(transport=httpx.MockTransport(handler))
    settings = Settings(environment="test", auto_create_tables=False, market_cache_seconds=0)
    service = MarketDataService(settings, client=client)
    try:
        result = await service.fetch_quotes(["USD", "EUR"])
    finally:
        await client.aclose()

    assert not result.quotes
    assert set(result.issues) == {"USD", "EUR"}
    assert called == []


def test_old_unverified_domestic_quotes_are_not_reused_as_last_known_prices() -> None:
    engine = create_engine("sqlite://", connect_args={"check_same_thread": False}, poolclass=StaticPool)
    Base.metadata.create_all(engine)
    now = datetime.now(timezone.utc)
    try:
        with Session(engine) as db:
            db.add_all([
                MarketQuoteRecord(
                    symbol=symbol, price=price, currency="IRT", provider=provider,
                    observed_at=now, unit=unit, market="IRAN",
                )
                for symbol, price, provider, unit in (
                    ("GOLD18", 20_000_000, "persian-toolbox", "gram_18k"),
                    ("USD", 235_000, "zarix", "currency_unit"),
                    ("EUR", 267_000, "zarix", "currency_unit"),
                )
            ])
            db.commit()
            old_quotes = {row.symbol: row for row in db.query(MarketQuoteRecord).all()}
            opened = now - timedelta(hours=2)
            db.add_all([
                MarketCandleRecord(
                    symbol=symbol, timeframe="1h", provider=provider, currency="IRT",
                    opened_at=opened, closed_at=opened + timedelta(hours=1),
                    open=price, high=price, low=price, close=price,
                    unit=unit, market="IRAN", is_complete=True,
                )
                for symbol, price, provider, unit in (
                    ("GOLD18", 20_000_000, "persian-toolbox", "gram_18k"),
                    ("USD", 235_000, "zarix", "currency_unit"),
                    ("EUR", 267_000, "zarix", "currency_unit"),
                )
            ])
            db.add(MarketCandleRecord(
                symbol="GOLD18", timeframe="1h", provider="quote-collector", currency="IRT",
                opened_at=opened, closed_at=opened + timedelta(hours=1),
                open=20_000_000, high=20_000_000, low=20_000_000, close=20_000_000,
                unit="gram_18k", market="IRAN", is_complete=True,
                source_tick_ids=[old_quotes["GOLD18"].id],
            ))
            db.commit()
            history = MarketHistoryService()
            for symbol in ("GOLD18", "USD", "EUR"):
                assert history.latest_quote(db, symbol) is None
                assert history.build_quote_candles(db, symbol=symbol, timeframe="1m").inserted == 0
                assert history.get_candles(db, symbol, "1h") == []
            statuses = MarketStatusService().latest_statuses(
                db, symbols=("GOLD18", "USD", "EUR"), max_age_seconds=300,
            )
            assert all(status.status == "missing" for status in statuses)
            overview = MarketOverviewService().build(
                db, symbols=("GOLD18",), max_age_seconds=300,
            )
            assert overview[0].quote is None
            snapshot = MarketObservabilityService().market_snapshot(db)
            assert not any(symbol in snapshot["market_age_seconds"] for symbol in ("GOLD18", "USD", "EUR"))
            invalid = MarketCandle(
                symbol="GOLD18", timeframe="1h", provider="persian-toolbox", currency="IRT",
                opened_at=opened + timedelta(hours=1), closed_at=opened + timedelta(hours=2),
                open=20_000_000, high=20_000_000, low=20_000_000, close=20_000_000,
                unit="gram_18k", market="IRAN",
            )
            assert history.upsert_candles(db, [invalid]).rejected == 1
            unproven = invalid.model_copy(update={"provider": "quote-collector", "source_tick_ids": [old_quotes["GOLD18"].id]})
            assert history.upsert_candles(db, [unproven]).rejected == 1
            valid_quote = MarketQuoteRecord(
                symbol="GOLD18", price=21_000_000, currency="IRT", provider="navasan",
                observed_at=now, unit="gram_18k", market="IRAN",
            )
            db.add(valid_quote)
            db.commit()
            trusted = unproven.model_copy(update={
                "open": 21_000_000, "high": 21_000_000, "low": 21_000_000, "close": 21_000_000,
                "source_tick_ids": [valid_quote.id],
            })
            assert history.upsert_candles(db, [trusted]).inserted == 1
            assert len(history.get_candles(db, "GOLD18", "1h")) == 1
    finally:
        engine.dispose()


@pytest.mark.asyncio
async def test_wallex_candle_history_is_normalized() -> None:
    start = datetime(2026, 1, 1, tzinfo=timezone.utc)

    def handler(request: httpx.Request) -> httpx.Response:
        assert request.url.host == "api.wallex.ir"
        assert request.url.path == "/v1/udf/history"
        assert request.url.params["symbol"] == "BTCUSDT"
        assert request.url.params["resolution"] == "60"
        return httpx.Response(
            200,
            json={
                "s": "ok",
                "t": [int(start.timestamp())],
                "o": ["65000"],
                "h": ["66000"],
                "l": ["64000"],
                "c": ["65500"],
                "v": ["12.5"],
            },
        )

    client = httpx.AsyncClient(transport=httpx.MockTransport(handler))
    service = MarketDataService(Settings(environment="test", auto_create_tables=False), client=client)
    try:
        candles = await service.fetch_wallex_candles(
            symbol="BTC", timeframe="1h", start_at=start, end_at=start + timedelta(hours=2)
        )
    finally:
        await client.aclose()

    assert len(candles) == 1
    assert candles[0].symbol == "BTC"
    assert candles[0].currency == "USDT"
    assert candles[0].close == 65500
