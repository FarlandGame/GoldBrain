"""Public CoinGecko development fallback for tracked cryptocurrencies.

The historical endpoint supplies observed prices, not exchange OHLC. Each
sample is labelled as such and is never interpolated into missing intervals.
"""
from __future__ import annotations

import asyncio
import math
import time
from datetime import datetime, timedelta, timezone
from typing import Iterable

import httpx

from app.core.market_quality import DataQualityStatus, classify_freshness
from app.schemas.history import MarketCandle
from app.schemas.market import MarketQuote


COINGECKO_IDS: dict[str, str] = {
    "BTC": "bitcoin", "ETH": "ethereum", "USDT": "tether", "BNB": "binancecoin",
    "XRP": "ripple", "USDC": "usd-coin", "SOL": "solana", "TRX": "tron",
    "ZEC": "zcash", "HYPE": "hyperliquid", "DOGE": "dogecoin",
    "XMR": "monero", "LINK": "chainlink", "ADA": "cardano",
    "LEO": "leo-token", "XLM": "stellar", "BCH": "bitcoin-cash",
    "NEAR": "near", "UNI": "uniswap", "LTC": "litecoin",
}


class CoinGeckoError(RuntimeError):
    def __init__(self, message: str, *, kind: str = "upstream") -> None:
        super().__init__(message)
        self.kind = kind


def _positive(value: object) -> float | None:
    try:
        parsed = float(str(value))
    except (TypeError, ValueError):
        return None
    return parsed if math.isfinite(parsed) and parsed > 0 else None


class CoinGeckoProvider:
    """One batched quote request per minute; no subscription is required."""

    def __init__(
        self,
        client: httpx.AsyncClient,
        *,
        base_url: str,
        demo_api_key: str = "",
        min_quote_interval_seconds: int = 60,
    ) -> None:
        self.client = client
        self.base_url = httpx.URL(base_url)
        if self.base_url.scheme != "https":
            raise ValueError("CoinGecko endpoint must use HTTPS")
        self.demo_api_key = demo_api_key.strip()
        self.min_quote_interval_seconds = max(0, min_quote_interval_seconds)
        self._lock = asyncio.Lock()
        self._last_quote_attempt = 0.0
        self._quotes: dict[str, MarketQuote] = {}

    def _headers(self) -> dict[str, str]:
        return {"x-cg-demo-api-key": self.demo_api_key} if self.demo_api_key else {}

    async def batch_quotes(self, symbols: Iterable[str]) -> dict[str, MarketQuote]:
        wanted = {symbol.strip().upper() for symbol in symbols if symbol.strip().upper() in COINGECKO_IDS}
        if not wanted:
            return {}
        async with self._lock:
            if time.monotonic() - self._last_quote_attempt < self.min_quote_interval_seconds:
                return {symbol: self._quotes[symbol] for symbol in wanted if symbol in self._quotes}
            self._last_quote_attempt = time.monotonic()
            started = time.perf_counter()
            try:
                response = await self.client.get(
                    str(self.base_url.join("simple/price")),
                    headers=self._headers(),
                    params={
                        "ids": ",".join(sorted(COINGECKO_IDS[symbol] for symbol in wanted)),
                        "vs_currencies": "usd",
                        "include_last_updated_at": "true",
                        "include_24hr_change": "true",
                    },
                )
            except httpx.HTTPError as exc:
                raise CoinGeckoError("CoinGecko development prices are unavailable.", kind="network") from exc
            if response.status_code == 429:
                raise CoinGeckoError("CoinGecko public request limit was reached.", kind="rate_limit")
            if response.status_code != 200:
                raise CoinGeckoError("CoinGecko development price request failed.")
            try:
                body = response.json()
            except ValueError as exc:
                raise CoinGeckoError("CoinGecko returned invalid price JSON.") from exc
            if not isinstance(body, dict):
                raise CoinGeckoError("CoinGecko returned an invalid price batch.")
            received_at = datetime.now(timezone.utc)
            latency_ms = int((time.perf_counter() - started) * 1000)
            result: dict[str, MarketQuote] = {}
            for symbol in wanted:
                item = body.get(COINGECKO_IDS[symbol])
                if not isinstance(item, dict):
                    continue
                price = _positive(item.get("usd"))
                timestamp = _positive(item.get("last_updated_at"))
                if price is None or timestamp is None:
                    continue
                observed = datetime.fromtimestamp(timestamp, tz=timezone.utc)
                if observed > received_at + timedelta(seconds=30):
                    continue
                raw_change = item.get("usd_24h_change")
                change = float(raw_change) if isinstance(raw_change, (int, float)) and math.isfinite(raw_change) else None
                freshness = classify_freshness(observed, now=received_at).value
                result[symbol] = MarketQuote(
                    asset=symbol, symbol=symbol, name=symbol, currency="USD",
                    price=price, updated_at=observed, provider="coingecko",
                    provider_timestamp=observed, received_at=received_at,
                    latency_ms=latency_ms, change_percent=change,
                    upstream_source=COINGECKO_IDS[symbol],
                    freshness_status=freshness, freshness=freshness,
                    data_quality_status=DataQualityStatus.VALID.value,
                    unit="coin", market="GLOBAL",
                )
            self._quotes.update(result)
            return {symbol: self._quotes[symbol] for symbol in wanted if symbol in self._quotes}

    async def price_samples(
        self, symbol: str, timeframe: str, start_at: datetime, end_at: datetime,
    ) -> list[MarketCandle]:
        symbol = symbol.strip().upper()
        coin_id = COINGECKO_IDS.get(symbol)
        if coin_id is None or timeframe not in {"1m", "1h"}:
            raise CoinGeckoError("CoinGecko has no matching price sample series.", kind="unsupported")
        if end_at <= start_at:
            raise CoinGeckoError("CoinGecko sample range is invalid.", kind="invalid_range")
        days = 1 if timeframe == "1m" else max(1, min(30, math.ceil((end_at - start_at).total_seconds() / 86400)))
        started = time.perf_counter()
        try:
            response = await self.client.get(
                str(self.base_url.join(f"coins/{coin_id}/market_chart")),
                headers=self._headers(),
                params={
                    "vs_currency": "usd", "days": str(days),
                    **({"interval": "hourly"} if timeframe == "1h" else {}),
                },
            )
        except httpx.HTTPError as exc:
            raise CoinGeckoError("CoinGecko development history is unavailable.", kind="network") from exc
        if response.status_code == 429:
            raise CoinGeckoError("CoinGecko public request limit was reached.", kind="rate_limit")
        if response.status_code != 200:
            raise CoinGeckoError("CoinGecko development history request failed.")
        try:
            body = response.json()
        except ValueError as exc:
            raise CoinGeckoError("CoinGecko returned invalid history JSON.") from exc
        points = body.get("prices") if isinstance(body, dict) else None
        if not isinstance(points, list):
            raise CoinGeckoError("CoinGecko returned no price samples.")
        received_at = datetime.now(timezone.utc)
        latency_ms = int((time.perf_counter() - started) * 1000)
        delta = timedelta(minutes=1) if timeframe == "1m" else timedelta(hours=1)
        by_open: dict[datetime, MarketCandle] = {}
        for point in points:
            if not isinstance(point, list) or len(point) != 2:
                continue
            timestamp = _positive(point[0])
            price = _positive(point[1])
            if timestamp is None or price is None:
                continue
            observed = datetime.fromtimestamp(timestamp / 1000, tz=timezone.utc)
            opened = observed.replace(second=0, microsecond=0)
            if timeframe == "1h":
                opened = opened.replace(minute=0)
            closed = opened + delta
            if opened < start_at - delta or closed > end_at or closed > received_at:
                continue
            by_open[opened] = MarketCandle(
                symbol=symbol, timeframe=timeframe, currency="USD",
                provider="coingecko", upstream_source=coin_id,
                opened_at=opened, closed_at=closed,
                open=price, high=price, low=price, close=price, volume=None,
                unit="coin", market="GLOBAL", provider_timestamp=observed,
                received_at=received_at, latency_ms=latency_ms,
                freshness_status=classify_freshness(observed, now=received_at).value,
                data_quality_status=DataQualityStatus.UNVERIFIED.value,
                quality_flags=["price_sample_not_ohlc"], is_complete=True,
            )
        return [by_open[key] for key in sorted(by_open)]
