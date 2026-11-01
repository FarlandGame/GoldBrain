"""Source-labelled index and financial-news evidence for Phase 2.

The endpoint never substitutes another country's market for an unavailable
index. Yahoo's public chart endpoint is useful for development but is not a
licensed production data contract. GDELT tone is optional evidence.
"""

from __future__ import annotations

import asyncio
import math
import time
from datetime import datetime, timedelta, timezone
from typing import Any

import httpx


COUNTRY_INDEX = {
    "usa": ("^GSPC", "S&P 500", "USD", "United States"),
    "germany": ("^GDAXI", "DAX", "EUR", "Germany"),
    "japan": ("^N225", "Nikkei 225", "JPY", "Japan"),
    "china": ("000001.SS", "SSE Composite", "CNY", "China"),
    "france": ("^FCHI", "CAC 40", "EUR", "France"),
    "iran": ("TEDPIX", "Tehran Exchange Price Index", "INDEX", "Iran"),
}
TEDPIX_INSCODE = "32097828799138957"
WINDOWS = {"24h": timedelta(days=1), "7d": timedelta(days=7), "30d": timedelta(days=30)}


class CountryPulseDataService:
    def __init__(
        self,
        client: httpx.AsyncClient | None = None,
        gdelt_min_interval_seconds: float = 5.2,
    ) -> None:
        self._client = client or httpx.AsyncClient(timeout=10.0, headers={"User-Agent": "GoldBrain/0.3 market-pulse"})
        self._owns_client = client is None
        self._cache: dict[tuple[str, str], tuple[datetime, dict[str, Any]]] = {}
        self._cache_locks: dict[tuple[str, str], asyncio.Lock] = {}
        self._gdelt_lock = asyncio.Lock()
        self._gdelt_min_interval_seconds = gdelt_min_interval_seconds
        self._last_gdelt_request_at: float | None = None

    async def close(self) -> None:
        if self._owns_client:
            await self._client.aclose()

    async def get(self, country: str, window: str) -> dict[str, Any]:
        if country not in COUNTRY_INDEX or window not in WINDOWS:
            raise ValueError("Unsupported country or window")
        key = (country, window)
        now = datetime.now(timezone.utc)
        cached = self._cache.get(key)
        if cached and now - cached[0] < timedelta(minutes=20):
            return cached[1]
        async with self._cache_locks.setdefault(key, asyncio.Lock()):
            cached = self._cache.get(key)
            if cached and datetime.now(timezone.utc) - cached[0] < timedelta(minutes=20):
                return cached[1]
            symbol, name, currency, search_country = COUNTRY_INDEX[country]
            result: dict[str, Any] = {
                "country": country,
                "window": window,
                "index_symbol": symbol,
                "index_name": name,
                "currency": currency,
                "unit": "index_points",
                "index_provider": "TSETMC" if country == "iran" else "Yahoo Finance public chart",
                "index_source_url": "https://www.tsetmc.com/" if country == "iran" else "https://finance.yahoo.com/markets/world-indices/",
                "index_status": "unavailable",
                "index_points": [],
                "last_observation_at": None,
                "news_provider": "GDELT DOC 2.0",
                "news_status": "unavailable",
                "news_tone": None,
                "news_source_url": "https://blog.gdeltproject.org/gdelt-doc-2-0-api-debuts/",
                "checked_at": now.isoformat(),
            }
            index_request = (
                self._iran_history(window, now)
                if country == "iran"
                else self._yahoo_history(symbol, currency, window, now)
            )
            index_result, news_result = await asyncio.gather(
                index_request,
                self._gdelt_tone(search_country, window),
                return_exceptions=True,
            )
            if isinstance(index_result, list):
                points = index_result
                result["index_points"] = points
                if points:
                    result["last_observation_at"] = points[-1]["time"]
                    last = datetime.fromisoformat(points[-1]["time"])
                    max_age = timedelta(hours=8) if window == "24h" else timedelta(days=4)
                    result["index_status"] = "stale" if now - last > max_age else "available"
            if isinstance(news_result, (int, float)) and math.isfinite(news_result):
                result["news_tone"] = news_result
                result["news_status"] = "available"
            self._cache[key] = (datetime.now(timezone.utc), result)
            return result

    async def _yahoo_history(
        self, symbol: str, currency: str, window: str, now: datetime
    ) -> list[dict[str, Any]]:
        params = {
            "range": "5d" if window == "24h" else "1mo" if window == "7d" else "3mo",
            "interval": "30m" if window == "24h" else "1d",
        }
        response = await self._client.get(
            f"https://query1.finance.yahoo.com/v8/finance/chart/{symbol}", params=params
        )
        response.raise_for_status()
        chart = response.json()["chart"]
        if chart.get("error") is not None:
            raise ValueError("Yahoo chart error")
        data = chart["result"][0]
        if data["meta"]["symbol"] != symbol or data["meta"]["currency"] != currency:
            raise ValueError("Wrong index identity or currency")
        closes = data["indicators"]["quote"][0]["close"]
        timestamps = data["timestamp"]
        cutoff = now - WINDOWS[window]
        points: dict[datetime, float] = {}
        for raw_time, raw_price in zip(timestamps, closes, strict=True):
            observed = datetime.fromtimestamp(raw_time, timezone.utc)
            if observed < cutoff or observed > now + timedelta(minutes=5):
                continue
            if not isinstance(raw_price, (int, float)) or not math.isfinite(raw_price) or raw_price <= 0:
                continue
            points[observed] = float(raw_price)
        return [{"time": time.isoformat(), "close": price} for time, price in sorted(points.items())]

    async def _iran_history(self, window: str, now: datetime) -> list[dict[str, Any]]:
        """Parse TSETMC daily TEDPIX closes; reject unknown shapes and dates.

        Requests from the VPN development host were inconclusive, so live
        access without VPN remains unverified. A trading-session date is encoded
        at UTC midnight only for ordering, not as an intraday source time.
        """
        response = await self._client.get(
            f"https://cdn.tsetmc.com/api/Index/GetIndexB2History/{TEDPIX_INSCODE}",
            headers={"User-Agent": "Mozilla/5.0 (GoldBrain private research)"},
        )
        response.raise_for_status()
        rows = response.json()["indexB2"]
        if not isinstance(rows, list):
            raise ValueError("Invalid TSETMC history")
        cutoff = now - WINDOWS[window]
        points: dict[datetime, float] = {}
        for row in rows:
            date_string = str(row["dEven"])
            if len(date_string) != 8 or not date_string.isdigit():
                raise ValueError("Invalid TSETMC session date")
            session = datetime.strptime(date_string, "%Y%m%d").replace(tzinfo=timezone.utc)
            price = row["xNivInuClMresIbs"]
            if not isinstance(price, (int, float)) or not math.isfinite(price) or price <= 0:
                raise ValueError("Invalid TEDPIX close")
            if cutoff <= session <= now:
                points[session] = float(price)
        return [{"time": time.isoformat(), "close": price} for time, price in sorted(points.items())]

    async def _gdelt_tone(self, country: str, window: str) -> float | None:
        # Optional news must never queue a pulse behind GDELT's rate limit.
        # A skipped request is explicitly labelled unavailable by the caller.
        async with self._gdelt_lock:
            now = time.monotonic()
            if (
                self._last_gdelt_request_at is not None
                and now - self._last_gdelt_request_at < self._gdelt_min_interval_seconds
            ):
                return None
            self._last_gdelt_request_at = now
        response = await self._client.get(
            "https://api.gdeltproject.org/api/v2/doc/doc",
            params={
                "query": f'"{country}" (economy OR inflation OR stockmarket OR finance)',
                "mode": "timelinetone",
                "format": "json",
                "timespan": window,
            },
            timeout=5.0,
        )
        response.raise_for_status()
        values = [
            float(point["value"])
            for series in response.json()["timeline"]
            for point in series["data"]
            if isinstance(point.get("value"), (int, float)) and math.isfinite(point["value"])
        ]
        return sum(values) / len(values) if values else None
