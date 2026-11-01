from __future__ import annotations

from datetime import datetime, timezone

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.market_quality import excluded_domestic_reference_providers
from app.models.forecast import ForecastRecord
from app.models.market import MarketQuoteRecord
from app.schemas.market import (
    DashboardAssetOverview,
    DashboardForecastSummary,
    MarketDataStatus,
    MarketQuote,
)
from app.services.market_status import MarketStatusService


class MarketOverviewService:
    """Read model for the private-beta dashboard without network side effects."""

    def build(
        self, db: Session, *, symbols: tuple[str, ...], max_age_seconds: int
    ) -> list[DashboardAssetOverview]:
        statuses = {
            item.symbol: item
            for item in MarketStatusService().latest_statuses(
                db, symbols=symbols, max_age_seconds=max_age_seconds
            )
        }
        return [self._asset(db, symbol=symbol, status=statuses[symbol]) for symbol in symbols]

    def _asset(self, db: Session, *, symbol: str, status: MarketDataStatus) -> DashboardAssetOverview:
        quote_query = select(MarketQuoteRecord).where(MarketQuoteRecord.symbol == symbol)
        excluded = excluded_domestic_reference_providers(symbol)
        if excluded:
            quote_query = quote_query.where(MarketQuoteRecord.provider.not_in(excluded))
        quote_row = db.scalar(quote_query.order_by(MarketQuoteRecord.observed_at.desc()).limit(1))
        forecast_row = db.scalar(
            select(ForecastRecord)
            .where(ForecastRecord.symbol == symbol)
            .order_by(ForecastRecord.generated_at.desc())
            .limit(1)
        )
        return DashboardAssetOverview(
            symbol=symbol,
            quote=_quote(quote_row) if quote_row else None,
            data_status=status,
            forecast=_forecast(forecast_row) if forecast_row else None,
        )


def _quote(row: MarketQuoteRecord) -> MarketQuote:
    return MarketQuote(
        symbol=row.symbol,
        name=row.symbol,
        currency=row.currency,
        price=row.price,
        updated_at=_utc(row.observed_at),
        provider=row.provider,
    )


def _forecast(row: ForecastRecord) -> DashboardForecastSummary:
    return DashboardForecastSummary(
        forecast_id=row.forecast_id,
        direction=row.direction,
        point_estimate=row.point_estimate,
        lower_bound=row.lower_bound,
        upper_bound=row.upper_bound,
        confidence_score=row.confidence_score,
        signal=row.signal,
        signal_quality=row.signal_quality,
        trade_allowed=row.trade_allowed,
        generated_at=_utc(row.generated_at),
        target_at=_utc(row.target_at),
    )


def _utc(value: datetime) -> datetime:
    if value.tzinfo is None:
        return value.replace(tzinfo=timezone.utc)
    return value.astimezone(timezone.utc)
