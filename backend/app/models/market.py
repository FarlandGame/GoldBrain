from __future__ import annotations

from datetime import datetime, timezone

from sqlalchemy import Boolean, JSON, DateTime, Index, Numeric, String
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base


class MarketAssetRecord(Base):
    __tablename__ = "market_assets"

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    symbol: Mapped[str] = mapped_column(String(24), unique=True)
    name: Mapped[str] = mapped_column(String(120))
    asset_class: Mapped[str] = mapped_column(String(32))
    quote_currency: Mapped[str] = mapped_column(String(12))
    unit: Mapped[str] = mapped_column(String(24))
    market: Mapped[str] = mapped_column(String(24))
    enabled: Mapped[bool] = mapped_column(Boolean, default=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc)
    )


class MarketQuoteRecord(Base):
    __tablename__ = "market_quotes"
    __table_args__ = (Index("ix_market_quotes_symbol_observed", "symbol", "observed_at"),)

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    symbol: Mapped[str] = mapped_column(String(24), index=True)
    price: Mapped[float] = mapped_column(Numeric(38, 18, asdecimal=False))
    currency: Mapped[str] = mapped_column(String(12))
    provider: Mapped[str] = mapped_column(String(32))
    upstream_source: Mapped[str | None] = mapped_column(String(120), nullable=True)
    observed_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), index=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))
    unit: Mapped[str] = mapped_column(String(24), default="unknown")
    market: Mapped[str] = mapped_column(String(24), default="unknown")
    provider_timestamp: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    received_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    latency_ms: Mapped[int | None] = mapped_column(nullable=True)
    freshness_status: Mapped[str] = mapped_column(String(16), default="FRESH")
    data_quality_status: Mapped[str] = mapped_column(String(16), default="VALID")
    quality_flags: Mapped[list[str] | None] = mapped_column(JSON, nullable=True)
    fallback_from: Mapped[str | None] = mapped_column(String(32), nullable=True)
    provider_spread_percent: Mapped[float | None] = mapped_column(Numeric(38, 12, asdecimal=False), nullable=True)
    content_fingerprint: Mapped[str | None] = mapped_column(String(96), unique=True, nullable=True)
