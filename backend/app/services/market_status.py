from __future__ import annotations

from datetime import datetime, timezone
from typing import Iterable

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models.market import MarketQuoteRecord
from app.schemas.market import MarketDataStatus
from app.core.market_quality import classify_freshness, excluded_domestic_reference_providers


class MarketStatusService:
    def latest_statuses(
        self, db: Session, *, symbols: Iterable[str], max_age_seconds: int
    ) -> list[MarketDataStatus]:
        now = datetime.now(timezone.utc)
        statuses: list[MarketDataStatus] = []
        for symbol in dict.fromkeys(item.strip().upper() for item in symbols if item.strip()):
            query = select(MarketQuoteRecord).where(MarketQuoteRecord.symbol == symbol)
            excluded = excluded_domestic_reference_providers(symbol)
            if excluded:
                query = query.where(MarketQuoteRecord.provider.not_in(excluded))
            row = db.scalar(query.order_by(MarketQuoteRecord.observed_at.desc()).limit(1))
            if row is None:
                statuses.append(
                    MarketDataStatus(
                        symbol=symbol,
                        status="missing",
                        freshness_status="UNAVAILABLE",
                        data_quality_status="INVALID",
                    )
                )
                continue
            observed_at = _utc(row.observed_at)
            age_seconds = max(0, int((now - observed_at).total_seconds()))
            statuses.append(
                MarketDataStatus(
                    symbol=symbol,
                    status="fresh" if age_seconds <= max_age_seconds else "stale",
                    provider=row.provider,
                    observed_at=observed_at,
                    age_seconds=age_seconds,
                    freshness_status=classify_freshness(observed_at, now=now).value,
                    data_quality_status=row.data_quality_status,
                    last_successful_update=_utc(row.received_at or row.observed_at),
                )
            )
        return statuses


def _utc(value: datetime) -> datetime:
    if value.tzinfo is None:
        return value.replace(tzinfo=timezone.utc)
    return value.astimezone(timezone.utc)
