"""Requested Wallex assets: native units, honest unavailability and candle routing."""
from datetime import datetime, timedelta, timezone

import httpx
import pytest

from app.core.config import Settings
from app.core.market_quality import ADDITIONAL_WALLEX_ASSETS, TRACKED_CRYPTO_TOP20
from app.services.market_data import SUPPORTED_ASSETS, MarketDataService

PRICES = {"DOT": 1.128, "PAXG": 4102, "NOT": 0.000396, "AVAX": 9.92,
          "TON": 1.99, "PEPE": 0.0000039, "ARB": 0.1849}


@pytest.mark.asyncio
async def test_requested_assets_share_one_wallex_snapshot_without_rounding_or_gold_alias() -> None:
    calls = []

    def respond(request: httpx.Request) -> httpx.Response:
        calls.append(request.url.path)
        assert request.url.host == "api.wallex.ir"
        return httpx.Response(200, json={"result": {"symbols": {
            symbol + "USDT": {"stats": {"lastPrice": str(price)}}
            for symbol, price in PRICES.items()
        }}})

    async with httpx.AsyncClient(transport=httpx.MockTransport(respond)) as client:
        service = MarketDataService(Settings(environment="test", auto_create_tables=False), client=client)
        batch = await service.fetch_quotes(PRICES)
    assert calls == ["/v1/markets"]
    assert not batch.issues
    for symbol, price in PRICES.items():
        quote = batch.quotes[symbol]
        assert quote.price == price
        assert quote.provider == "wallex" and quote.currency == "USDT"
        assert quote.upstream_source == symbol + "USDT"
        assert quote.unit == "coin"
        assert quote.provider_timestamp is None
        assert quote.freshness == "DELAYED"
    assert "XAU" not in batch.quotes
    assert batch.quotes["PEPE"].price > 0


@pytest.mark.parametrize("price", ["-", None, "0", "-1"])
@pytest.mark.asyncio
async def test_unavailable_ton_does_not_turn_into_a_live_zero_or_an_invented_price(price: object) -> None:
    calls = []

    def respond(request: httpx.Request) -> httpx.Response:
        calls.append(request.url.host)
        return httpx.Response(200, json={"result": {"symbols": {
            "TONUSDT": {"stats": {"lastPrice": price}},
            "BTCUSDT": {"stats": {"lastPrice": "81000"}},
        }}})

    async with httpx.AsyncClient(transport=httpx.MockTransport(respond)) as client:
        service = MarketDataService(Settings(environment="test", auto_create_tables=False), client=client)
        batch = await service.fetch_quotes(["TON"])
    assert "TON" not in batch.quotes
    assert "TON" in batch.issues
    assert calls == ["api.wallex.ir"]


@pytest.mark.parametrize("symbol", PRICES)
@pytest.mark.asyncio
async def test_requested_asset_history_uses_its_own_wallex_usdt_pair(symbol: str) -> None:
    end = datetime.now(timezone.utc).replace(minute=0, second=0, microsecond=0)
    start = end - timedelta(days=7)
    opening = end - timedelta(hours=2)

    def respond(request: httpx.Request) -> httpx.Response:
        assert request.url.path == "/v1/udf/history"
        assert request.url.params["symbol"] == symbol + "USDT"
        assert request.url.params["resolution"] == "60"
        return httpx.Response(200, json={"s": "ok", "t": [int(opening.timestamp())],
                                       "o": [1], "h": [2], "l": [0.5], "c": [1.5], "v": [5]})

    async with httpx.AsyncClient(transport=httpx.MockTransport(respond)) as client:
        service = MarketDataService(Settings(environment="test", auto_create_tables=False), client=client)
        candles = await service.fetch_wallex_candles(symbol=symbol, timeframe="1h", start_at=start, end_at=end)
    assert len(candles) == 1
    assert candles[0].symbol == symbol
    assert candles[0].currency == "USDT"
    assert candles[0].upstream_source == symbol + "USDT"
    assert candles[0].close == 1.5


def test_catalog_additions_do_not_relabel_the_dated_top20_or_enable_forecasts() -> None:
    assert len(TRACKED_CRYPTO_TOP20) == 20
    requested = dict(ADDITIONAL_WALLEX_ASSETS)
    assert set(requested) == set(PRICES)
    catalog = {asset.symbol: asset for asset in SUPPORTED_ASSETS}
    for symbol in requested:
        assert catalog[symbol].quote_currency == "USDT"
        assert catalog[symbol].asset_class == "crypto"
        assert not catalog[symbol].forecast
    assert catalog["PAXG"].symbol != catalog["XAU"].symbol
