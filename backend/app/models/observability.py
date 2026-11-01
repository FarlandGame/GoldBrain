from __future__ import annotations

from datetime import datetime, timezone

from sqlalchemy import DateTime, Index, Integer, String
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base


class MarketProviderMetricRecord(Base):
    """Sanitized provider telemetry; request URLs and secrets are never stored."""

    __tablename__ = "market_provider_metrics"
    __table_args__ = (Index("ix_market_provider_metrics_observed", "observed_at"),)

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    provider: Mapped[str] = mapped_column(String(40), index=True)
    operation: Mapped[str] = mapped_column(String(32))
    status: Mapped[str] = mapped_column(String(16))
    latency_ms: Mapped[int | None] = mapped_column(Integer, nullable=True)
    error_kind: Mapped[str | None] = mapped_column(String(32), nullable=True)
    fallback_used: Mapped[bool] = mapped_column(default=False)
    observed_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc)
    )
