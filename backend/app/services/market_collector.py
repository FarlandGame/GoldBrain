from __future__ import annotations

from dataclasses import dataclass
from typing import Iterable

from sqlalchemy.orm import Session

from app.services.history import MarketHistoryService, UpsertResult
from app.services.market_data import MarketDataService

PRIVATE_BETA_SYMBOLS: tuple[str, ...] = ("GOLD18", "USDT", "BTC")
REFERENCE_SYMBOLS: tuple[str, ...] = ("XAU",)
DEFAULT_COLLECTION_SYMBOLS = PRIVATE_BETA_SYMBOLS + REFERENCE_SYMBOLS


@dataclass(frozen=True)
class MarketCollectionResult:
    requested_symbols: tuple[str, ...]
    collected_quotes: int
    quote_issues: dict[str, str]
    candles: dict[str, UpsertResult]


class MarketCollector:
    """Collect one honest snapshot for the three-asset private beta.

    Scheduling is deliberately external (Task Scheduler, container scheduler or
    a future worker). This keeps API request handling free of long-lived jobs
    and makes every collection run observable and testable.
    """

    def __init__(
        self,
        market_data: MarketDataService,
        history: MarketHistoryService | None = None,
    ) -> None:
        self.market_data = market_data
        self.history = history or MarketHistoryService()

    async def collect_once(
        self,
        db: Session,
        *,
        symbols: Iterable[str] = DEFAULT_COLLECTION_SYMBOLS,
        candle_timeframe: str = "1m",
    ) -> MarketCollectionResult:
        requested = tuple(dict.fromkeys(symbol.strip().upper() for symbol in symbols if symbol.strip()))
        batch = await self.market_data.fetch_quotes(requested, force_refresh=True)
        collected = self.history.persist_quotes(db, batch.quotes.values())
        candles = {
            symbol: self.history.build_quote_candles(
                db,
                symbol=symbol,
                timeframe=candle_timeframe,
                lookback_hours=72,
            )
            for symbol in batch.quotes
        }
        return MarketCollectionResult(
            requested_symbols=requested,
            collected_quotes=collected,
            quote_issues=batch.issues,
            candles=candles,
        )
