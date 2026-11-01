"""Phase 1 provider-boundary tests; none require or spend a live API key."""
from __future__ import annotations

from datetime import datetime, timedelta, timezone
from zoneinfo import ZoneInfo

import httpx
import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import Session
from sqlalchemy.pool import StaticPool

from app.api.routes.history import asset_candles, asset_price_samples
from app.core.config import Settings
from app.db.base import Base
from app.models.market import MarketQuoteRecord
from app.services.coingecko import CoinGeckoProvider
from app.services.market_data import MarketDataService, _navasan_jalali_date


@pytest.mark.asyncio
async def test_navasan_24h_samples_are_real_prices_with_tehran_dates_and_toman_boundary() -> None:
    now = datetime.now(timezone.utc).replace(microsecond=0)
    tehran = ZoneInfo("Asia/Tehran")
    observed = [now - timedelta(hours=20), now - timedelta(hours=1)]
    requests: list[tuple[str, str]] = []

    def respond(request: httpx.Request) -> httpx.Response:
        assert request.url.path == "/dailyCurrency/"
        item = request.url.params["item"]
        day = request.url.params["date"]
        requests.append((item, day))
        rows = [
            {"timestamp": str(int(timestamp.timestamp())), "value": "234000"}
            for timestamp in observed
            if _navasan_jalali_date(timestamp.astimezone(tehran).date()) == day
        ]
        # An explicit rial field is divided at the provider boundary, not in
        # the Flutter chart. Duplicate source timestamps do not create points.
        if rows:
            rows[-1] = {**rows[-1], "currency": "IRR", "value": "2340000"}
            rows.append(dict(rows[-1]))
        return httpx.Response(200, json=rows)

    async with httpx.AsyncClient(transport=httpx.MockTransport(respond)) as client:
        service = MarketDataService(Settings(environment="test", auto_create_tables=False,
                                            NAVASAN_API_KEY="local-test-key"), client=client)
        first = await service.fetch_navasan_intraday_samples(
            symbol="USD", start_at=now - timedelta(hours=24), end_at=now,
        )
        second = await service.fetch_navasan_intraday_samples(
            symbol="USD", start_at=now - timedelta(hours=24), end_at=now,
        )
    assert [sample.provider_timestamp for sample in first] == observed
    assert all(sample.price == 234000 and sample.currency == "IRT" for sample in first)
    assert all(sample.data_quality_status == "VALID" for sample in first)
    assert all("unit_from_provider_catalog" not in sample.quality_flags for sample in first)
    assert all("price_sample_not_ohlc" in sample.quality_flags for sample in first)
    assert first == second
    assert len(requests) <= 2
    assert {day for _, day in requests} == {
        _navasan_jalali_date(timestamp.astimezone(tehran).date())
        for timestamp in (now - timedelta(hours=24), now)
    }


def test_navasan_jalali_date_boundary() -> None:
    from datetime import date

    assert _navasan_jalali_date(date(2026, 3, 20)) == "1404-12-29"
    assert _navasan_jalali_date(date(2026, 3, 21)) == "1405-01-01"
    assert _navasan_jalali_date(date(2026, 9, 26)) == "1405-07-04"


@pytest.mark.asyncio
async def test_eur_24h_samples_use_persisted_source_times_without_dailycurrency() -> None:
    now = datetime.now(timezone.utc).replace(microsecond=0)
    engine = create_engine("sqlite://", connect_args={"check_same_thread": False}, poolclass=StaticPool)
    Base.metadata.create_all(engine)
    try:
        with Session(engine) as db:
            for hours_ago, price in ((12, 265000), (2, 266000)):
                observed = now - timedelta(hours=hours_ago)
                legacy = hours_ago == 12
                db.add(MarketQuoteRecord(
                    symbol="EUR", price=price, currency="IRT", provider="navasan",
                    upstream_source="eur", observed_at=observed,
                    provider_timestamp=observed, received_at=observed,
                    unit="currency_unit", market="IRAN",
                    data_quality_status="UNVERIFIED" if legacy else "VALID",
                    quality_flags=["unit_from_provider_catalog", "provider_unverified"] if legacy else [],
                ))
            db.commit()
            async with httpx.AsyncClient(transport=httpx.MockTransport(
                lambda request: pytest.fail("EUR must not call /dailyCurrency")
            )) as client:
                market_data = MarketDataService(Settings(environment="test", auto_create_tables=False,
                                                         NAVASAN_API_KEY="local-test-key"), client=client)
                response = await asset_price_samples("EUR", "24h", db, market_data)
        assert [sample.price for sample in response.samples] == [265000, 266000]
        assert all(sample.provider == "navasan" and "price_sample_not_ohlc" in sample.quality_flags
                   for sample in response.samples)
        assert all(sample.data_quality_status == "VALID" and "unit_from_provider_catalog" not in sample.quality_flags
                   for sample in response.samples)
    finally:
        engine.dispose()


@pytest.mark.asyncio
async def test_navasan_recorded_latest_shape_keeps_domestic_units_explicit() -> None:
    """Real `/latest/` items omit unit/currency even though prices are numeric."""
    recorded = {
        "usd_sell": {"value": "234000", "timestamp": "1790443915", "change": 500, "date": "1405-07-04"},
        "eur": {"value": "266540", "timestamp": "1790443915", "change": 450, "date": "1405-07-04"},
        "18ayar": {"value": "23858440", "timestamp": "1790447413", "change": 126970, "date": "1405-07-04"},
    }

    async with httpx.AsyncClient(transport=httpx.MockTransport(
        lambda request: httpx.Response(200, json=recorded)
    )) as client:
        service = MarketDataService(Settings(environment="test", auto_create_tables=False,
                                            NAVASAN_API_KEY="local-test-key"), client=client)
        quotes = await service._fetch_navasan()

    assert {symbol: quote.price for symbol, quote in quotes.items()} == {
        "USD": 234000, "EUR": 266540, "GOLD18": 23858440,
    }
    assert all(quote.provider == "navasan" and quote.currency == "IRT" for quote in quotes.values())
    assert all(quote.data_quality_status == "VALID" for quote in quotes.values())
    assert all("unit_from_provider_catalog" not in quote.quality_flags for quote in quotes.values())
    assert quotes["USD"].unit == quotes["EUR"].unit == "currency_unit"
    assert quotes["GOLD18"].unit == "gram_18k"
    assert quotes["USD"].provider_timestamp == datetime.fromtimestamp(1790443915, tz=timezone.utc)


@pytest.mark.asyncio
async def test_navasan_explicit_rial_is_converted_once_to_toman() -> None:
    observed = int(datetime.now(timezone.utc).timestamp())

    async with httpx.AsyncClient(transport=httpx.MockTransport(
        lambda request: httpx.Response(200, json={
            "usd_sell": {"value": "2340000", "change": "5000", "currency": "IRR",
                         "timestamp": observed},
            "eur": {"value": "266540", "change": "450", "timestamp": observed},
            "18ayar": {"value": "238584400", "currency": "IRR", "timestamp": observed},
        })
    )) as client:
        service = MarketDataService(Settings(environment="test", auto_create_tables=False,
                                            NAVASAN_API_KEY="local-test-key"), client=client)
        quotes = await service._fetch_navasan()
    assert quotes["USD"].price == 234000
    assert quotes["USD"].change_percent == pytest.approx(500 / 233500 * 100)
    assert quotes["EUR"].price == 266540
    assert quotes["GOLD18"].price == 23858440
    assert all(quote.currency == "IRT" and quote.data_quality_status == "VALID"
               for quote in quotes.values())


@pytest.mark.asyncio
async def test_navasan_daily_explicit_rial_ohlc_is_converted_once() -> None:
    tehran = ZoneInfo("Asia/Tehran")
    day = datetime.now(tehran).date() - timedelta(days=1)
    observed = datetime.combine(day, datetime.min.time(), tzinfo=tehran)

    async with httpx.AsyncClient(transport=httpx.MockTransport(
        lambda request: httpx.Response(200, json=[{
            "timestamp": int(observed.timestamp()), "currency": "IRR",
            "open": "2330000", "high": "2341000", "low": "2325000", "close": "2338000",
        }])
    )) as client:
        service = MarketDataService(Settings(environment="test", auto_create_tables=False,
                                            NAVASAN_API_KEY="local-test-key"), client=client)
        rows = await service.fetch_navasan_daily_candles(
            symbol="USD", start_at=(observed - timedelta(days=1)).astimezone(timezone.utc),
            end_at=datetime.now(timezone.utc),
        )
    assert len(rows) == 1
    assert (rows[0].open, rows[0].high, rows[0].low, rows[0].close) == (
        233000, 234100, 232500, 233800,
    )
    assert rows[0].currency == "IRT" and rows[0].data_quality_status == "VALID"


@pytest.mark.asyncio
async def test_navasan_daily_string_prices_do_not_close_current_session() -> None:
    """`/ohlcSearch/` includes the still-open Tehran day; it is not a closed candle."""
    tehran = ZoneInfo("Asia/Tehran")
    today = datetime.now(tehran).date()
    current_open = datetime.combine(today, datetime.min.time(), tzinfo=tehran)
    previous_open = current_open - timedelta(days=1)
    provider_rows = [
        {"timestamp": str(int(previous_open.timestamp())),
         "open": "233000", "high": "234100", "low": "232500", "close": "233800"},
        {"timestamp": str(int(current_open.timestamp())),
         "open": "234200", "high": "234800", "low": "233100", "close": "233800"},
    ]

    async with httpx.AsyncClient(transport=httpx.MockTransport(
        lambda request: httpx.Response(200, json=provider_rows)
    )) as client:
        service = MarketDataService(Settings(environment="test", auto_create_tables=False,
                                            NAVASAN_API_KEY="local-test-key"), client=client)
        candles = await service.fetch_navasan_daily_candles(
            symbol="USD", start_at=(previous_open - timedelta(days=1)).astimezone(timezone.utc),
            end_at=datetime.now(timezone.utc),
        )

    assert len(candles) == 2
    assert candles[0].is_complete is True
    assert candles[1].is_complete is False
    assert candles[1].currency == "IRT"
    assert candles[1].upstream_source == "usd_sell"
    assert candles[1].opened_at == current_open.astimezone(timezone.utc)


@pytest.mark.asyncio
async def test_navasan_uses_toman_and_rejects_mismatched_currency() -> None:
    observed = datetime.now(timezone.utc).replace(microsecond=0)
    requests: list[httpx.Request] = []

    def respond(request: httpx.Request) -> httpx.Response:
        requests.append(request)
        return httpx.Response(200, json={
            "18ayar": {"value": "12000000", "timestamp": int(observed.timestamp())},
            "usd_sell": {"value": "99000", "currency": "USD", "timestamp": int(observed.timestamp())},
        })

    async with httpx.AsyncClient(transport=httpx.MockTransport(respond)) as client:
        service = MarketDataService(Settings(environment="test", auto_create_tables=False,
                                            NAVASAN_API_KEY="local-test-key"), client=client)
        quotes = await service._fetch_navasan()
    assert requests[0].url.host == "api.navasan.tech"
    assert quotes["GOLD18"].price == 12_000_000
    assert quotes["GOLD18"].currency == "IRT"
    assert quotes["GOLD18"].unit == "gram_18k"
    assert quotes["GOLD18"].provider_timestamp == observed
    assert quotes["GOLD18"].received_at >= observed
    assert "USD" not in quotes


@pytest.mark.asyncio
async def test_navasan_free_poll_is_bounded_and_daily_history_keeps_real_sessions() -> None:
    now = datetime.now(timezone.utc)
    calls: list[str] = []

    def respond(request: httpx.Request) -> httpx.Response:
        calls.append(request.url.path)
        if request.url.path == "/latest/":
            return httpx.Response(200, json={
                "18ayar": {"value": "12000000", "timestamp": int(now.timestamp())},
            })
        if request.url.path == "/ohlcSearch/":
            return httpx.Response(200, json=[
                {
                    "timestamp": int((now - timedelta(days=2)).timestamp()),
                    "open": "12000000", "high": "12100000",
                    "low": "11900000", "close": "12050000",
                },
                {
                    "timestamp": int((now - timedelta(days=1)).timestamp()),
                    "open": "12050000", "high": "12200000",
                    "low": "12000000", "close": "12150000",
                },
            ])
        return httpx.Response(404)

    async with httpx.AsyncClient(transport=httpx.MockTransport(respond)) as client:
        service = MarketDataService(Settings(environment="test", auto_create_tables=False,
                                            NAVASAN_API_KEY="local-test-key"), client=client)
        first = await service._fetch_navasan()
        second = await service._fetch_navasan()
        candles = await service.fetch_navasan_daily_candles(
            symbol="GOLD18", start_at=now - timedelta(days=5), end_at=now,
        )
        repeated = await service.fetch_navasan_daily_candles(
            symbol="GOLD18", start_at=now - timedelta(days=5), end_at=now,
        )
    assert first == second
    assert repeated == []
    assert calls == ["/latest/", "/ohlcSearch/"]
    assert len(candles) == 2
    assert all(row.provider == "navasan" and row.currency == "IRT" for row in candles)
    assert all(row.unit == "gram_18k" and row.is_complete for row in candles)
    assert candles[0].opened_at < candles[1].opened_at


@pytest.mark.asyncio
async def test_navasan_daily_readthrough_is_idempotent() -> None:
    now = datetime.now(timezone.utc)
    calls = 0

    def respond(request: httpx.Request) -> httpx.Response:
        nonlocal calls
        calls += 1
        assert request.url.path == "/ohlcSearch/"
        assert request.url.params["item"] == "eur"
        return httpx.Response(200, json=[
            {
                "timestamp": int((now - timedelta(days=days_ago)).timestamp()),
                "open": "260000", "high": "265000", "low": "259000", "close": "264000",
            }
            for days_ago in range(34, 0, -1)
        ])

    engine = create_engine("sqlite://", connect_args={"check_same_thread": False}, poolclass=StaticPool)
    Base.metadata.create_all(engine)
    try:
        with Session(engine) as db:
            async with httpx.AsyncClient(transport=httpx.MockTransport(respond)) as client:
                service = MarketDataService(Settings(environment="test", auto_create_tables=False,
                                                    NAVASAN_API_KEY="local-test-key"), client=client)
                first = await asset_candles("EUR", "1d", 40, "navasan", None, None, db, service)
                again = await asset_candles("EUR", "1d", 40, "navasan", None, None, db, service)
        assert len(first.candles) == len(again.candles) == 34
        assert all(row.provider == "navasan" and row.currency == "IRT" for row in again.candles)
        assert calls == 1
    finally:
        engine.dispose()


@pytest.mark.asyncio
async def test_unverified_zarix_eur_quote_is_not_used_by_market_gateway() -> None:
    calls: list[str] = []
    def respond(request: httpx.Request) -> httpx.Response:
        calls.append(str(request.url))
        assert request.url.host == "zarix.online"
        assert request.url.params["category"] == "currencies"
        return httpx.Response(200, json={"ok": True, "data": {"items": [{
            "symbol": "EUR", "price": 267140, "unit": "تومان",
            "updatedAt": datetime.now(timezone.utc).isoformat(),
        }]}})

    async with httpx.AsyncClient(transport=httpx.MockTransport(respond)) as client:
        service = MarketDataService(Settings(environment="test", auto_create_tables=False), client=client)
        batch = await service.fetch_quotes(["EUR"])
    assert "EUR" not in batch.quotes
    assert "EUR" in batch.issues
    assert calls == []


@pytest.mark.asyncio
async def test_wallex_missing_source_timestamp_is_not_live() -> None:
    def respond(request: httpx.Request) -> httpx.Response:
        assert request.url.path == "/v1/markets"
        return httpx.Response(200, json={"result": {"symbols": {
            "BTCUSDT": {"stats": {"lastPrice": "65000", "24h_ch": 1.0}},
        }}})

    async with httpx.AsyncClient(transport=httpx.MockTransport(respond)) as client:
        service = MarketDataService(Settings(environment="test", auto_create_tables=False), client=client)
        quote = (await service.fetch_quotes(["BTC"])).quotes["BTC"]
    assert quote.provider_timestamp is None
    assert quote.received_at is not None
    assert quote.freshness_status == "DELAYED"
    assert "provider_timestamp_unavailable" in quote.quality_flags


@pytest.mark.asyncio
async def test_coingecko_fallback_keeps_usd_market_and_source_visible() -> None:
    observed = int(datetime.now(timezone.utc).timestamp())

    def respond(request: httpx.Request) -> httpx.Response:
        if request.url.host == "api.wallex.ir":
            return httpx.Response(503)
        if request.url.host == "api.coingecko.com":
            return httpx.Response(200, json={"monero": {
                "usd": 301.25, "last_updated_at": observed, "usd_24h_change": -0.5,
            }})
        return httpx.Response(503)

    async with httpx.AsyncClient(transport=httpx.MockTransport(respond)) as client:
        service = MarketDataService(Settings(environment="test", auto_create_tables=False), client=client)
        quote = (await service.fetch_quotes(["XMR"])).quotes["XMR"]
    assert quote.provider == "coingecko"
    assert quote.fallback_from == "wallex"
    assert quote.currency == "USD"
    assert quote.price == 301.25
    assert quote.provider_timestamp is not None


@pytest.mark.asyncio
async def test_stale_navasan_gold_never_uses_unverified_reference_fallback() -> None:
    stale = (datetime.now(timezone.utc) - timedelta(hours=2)).isoformat()
    called: list[str] = []

    def respond(request: httpx.Request) -> httpx.Response:
        called.append(str(request.url))
        if request.url.host == "api.navasan.tech":
            return httpx.Response(200, json={
                "18ayar": {"value": "20000000", "timestamp": int(datetime.fromisoformat(stale).timestamp())},
            })
        raise AssertionError("Unverified domestic fallback should not be called")

    async with httpx.AsyncClient(transport=httpx.MockTransport(respond)) as client:
        settings = Settings(environment="test", auto_create_tables=False,
                            NAVASAN_API_KEY="local-test-key")
        service = MarketDataService(settings, client=client)
        batch = await service.fetch_quotes(["GOLD18"])
    quote = batch.quotes["GOLD18"]
    assert quote.price == 20_000_000
    assert quote.provider == "navasan"
    assert quote.freshness_status == "STALE"
    assert "GOLD18" in batch.issues
    assert len(called) == 1


@pytest.mark.asyncio
async def test_coingecko_history_is_labelled_price_samples_not_ohlc() -> None:
    now = datetime.now(timezone.utc)
    first = now.replace(minute=10, second=0, microsecond=0) - timedelta(hours=3)

    def respond(request: httpx.Request) -> httpx.Response:
        assert request.url.path == "/api/v3/coins/leo-token/market_chart"
        return httpx.Response(200, json={"prices": [
            [int(first.timestamp() * 1000), 9.1],
            [int((first + timedelta(hours=1)).timestamp() * 1000), 9.2],
        ]})

    async with httpx.AsyncClient(transport=httpx.MockTransport(respond)) as client:
        provider = CoinGeckoProvider(client, base_url="https://api.coingecko.com/api/v3/")
        rows = await provider.price_samples("LEO", "1h", now - timedelta(days=1), now)
    assert len(rows) == 2
    assert rows[0].currency == "USD"
    assert rows[0].provider == "coingecko"
    assert rows[0].data_quality_status == "UNVERIFIED"
    assert rows[0].quality_flags == ["price_sample_not_ohlc"]
    assert rows[0].open == rows[0].high == rows[0].low == rows[0].close


@pytest.mark.asyncio
async def test_history_readthrough_is_idempotent_and_preserves_provider() -> None:
    now = datetime.now(timezone.utc).replace(minute=0, second=0, microsecond=0)
    starts = [int((now - timedelta(hours=i)).timestamp()) for i in (3, 2, 1)]
    calls = 0

    def respond(request: httpx.Request) -> httpx.Response:
        nonlocal calls
        calls += 1
        assert request.url.path == "/v1/udf/history"
        return httpx.Response(200, json={
            "s": "ok", "t": starts, "o": [100, 101, 102],
            "h": [102, 103, 104], "l": [99, 100, 101],
            "c": [101, 102, 103], "v": [1, 1, 1],
        })

    engine = create_engine("sqlite://", connect_args={"check_same_thread": False}, poolclass=StaticPool)
    Base.metadata.create_all(engine)
    try:
        with Session(engine) as db:
            async with httpx.AsyncClient(transport=httpx.MockTransport(respond)) as client:
                service = MarketDataService(Settings(environment="test", auto_create_tables=False), client=client)
                first = await asset_candles("BTC", "1h", 5, "wallex", None, None, db, service)
                again = await asset_candles("BTC", "1h", 5, "wallex", None, None, db, service)
        assert len(first.candles) == len(again.candles) == 3
        assert all(row.provider == "wallex" and row.currency == "USDT" for row in again.candles)
        assert calls == 2  # A short incomplete range can be retried without duplication.
    finally:
        engine.dispose()
