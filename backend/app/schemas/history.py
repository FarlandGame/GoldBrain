from __future__ import annotations

from datetime import datetime

from app.schemas.common import ApiModel


class MarketCandle(ApiModel):
    symbol: str
    timeframe: str
    currency: str
    provider: str
    upstream_source: str | None = None
    opened_at: datetime
    closed_at: datetime
    open: float
    high: float
    low: float
    close: float
    volume: float | None = None
    unit: str = "unknown"
    market: str = "unknown"
    provider_timestamp: datetime | None = None
    received_at: datetime | None = None
    latency_ms: int | None = None
    freshness_status: str = "FRESH"
    data_quality_status: str = "VALID"
    quality_flags: list[str] = []
    source_tick_ids: list[int] = []
    is_complete: bool = True


class CandleBatchIn(ApiModel):
    candles: list[MarketCandle]


class CandleBatchResult(ApiModel):
    inserted: int
    updated: int
    rejected: int


class ProviderCandleFetchResult(CandleBatchResult):
    symbol: str
    timeframe: str
    provider: str


class CandleHistoryResponse(ApiModel):
    symbol: str
    timeframe: str
    candles: list[MarketCandle]


class MarketPriceSample(ApiModel):
    """An observed provider price, never an inferred OHLC candle."""

    symbol: str
    price: float
    currency: str
    unit: str
    market: str
    provider: str
    upstream_source: str
    provider_timestamp: datetime
    received_at: datetime
    freshness_status: str
    data_quality_status: str
    quality_flags: list[str] = []


class PriceSampleHistoryResponse(ApiModel):
    symbol: str
    range: str
    samples: list[MarketPriceSample]
