"""Explicit market-data provider registry.

The registry documents the source order used by ``MarketDataService`` and is
also exposed to runbooks.  It deliberately contains no credentials or URLs.
"""
from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
from typing import Protocol

from app.schemas.market import MarketQuote
from app.schemas.history import MarketCandle


class MarketDataProvider(Protocol):
    """Adapter contract shared by primary, secondary and historical sources."""

    name: str

    async def quote(self, symbol: str) -> MarketQuote: ...

    async def candles(self, symbol: str, timeframe: str, start_at: datetime, end_at: datetime) -> list[MarketCandle]: ...


@dataclass(frozen=True)
class ProviderChain:
    asset: str
    primary: str
    secondary: tuple[str, ...]
    historical: tuple[str, ...]
    update_interval_seconds: int
    live_method: str = "polling"
    rate_limit_per_minute: int | None = None
    commercial_use: str = "verify provider terms before public launch"


PROVIDER_CHAINS: tuple[ProviderChain, ...] = (
    # The historical route currently wires Wallex UDF only. Nobitex UDF is a
    # documented candidate source but is not an automatic backfill path.
    ProviderChain("BTC", "wallex", ("nobitex", "coingecko", "zarix", "gold-api"), ("wallex",), 60, "polling", 120),
    ProviderChain("USDT", "wallex", ("nobitex", "navasan"), ("wallex",), 60, "polling", 120),
    ProviderChain("GOLD18", "navasan", (), (), 120, "polling", 60),
)


def provider_chain(asset: str) -> ProviderChain | None:
    normalized = asset.strip().upper()
    return next((item for item in PROVIDER_CHAINS if item.asset == normalized), None)
