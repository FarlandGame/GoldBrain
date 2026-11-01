from __future__ import annotations

from datetime import datetime, timezone

from sqlalchemy import JSON, DateTime, Index, Numeric, String, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base


class MarketCandleRecord(Base):
    """Normalized server-side OHLCV candle.

    A provider/source/timestamp tuple is immutable. Duplicate or revised
    upstream candles are rejected, and history is never fabricated.
    """

    __tablename__ = "market_candles"
    __table_args__ = (
        UniqueConstraint(
            "symbol", "timeframe", "provider", "opened_at", name="uq_market_candle_source_time"
        ),
        Index("ix_market_candles_symbol_tf_time", "symbol", "timeframe", "opened_at"),
    )

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    symbol: Mapped[str] = mapped_column(String(24), index=True)
    timeframe: Mapped[str] = mapped_column(String(12), index=True)
    currency: Mapped[str] = mapped_column(String(12))
    provider: Mapped[str] = mapped_column(String(40))
    upstream_source: Mapped[str | None] = mapped_column(String(160), nullable=True)
    opened_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), index=True)
    closed_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    open: Mapped[float] = mapped_column(Numeric(38, 18, asdecimal=False))
    high: Mapped[float] = mapped_column(Numeric(38, 18, asdecimal=False))
    low: Mapped[float] = mapped_column(Numeric(38, 18, asdecimal=False))
    close: Mapped[float] = mapped_column(Numeric(38, 18, asdecimal=False))
    volume: Mapped[float | None] = mapped_column(Numeric(38, 18, asdecimal=False), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))
    unit: Mapped[str] = mapped_column(String(24), default="unknown")
    market: Mapped[str] = mapped_column(String(24), default="unknown")
    provider_timestamp: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    received_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    latency_ms: Mapped[int | None] = mapped_column(nullable=True)
    freshness_status: Mapped[str] = mapped_column(String(16), default="FRESH")
    data_quality_status: Mapped[str] = mapped_column(String(16), default="VALID")
    quality_flags: Mapped[list[str] | None] = mapped_column(JSON, nullable=True)
    source_tick_ids: Mapped[list[int] | None] = mapped_column(JSON, nullable=True)
    is_complete: Mapped[bool] = mapped_column(default=True)
    content_fingerprint: Mapped[str | None] = mapped_column(String(96), unique=True, nullable=True)
