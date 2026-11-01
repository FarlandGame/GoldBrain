from __future__ import annotations

from datetime import datetime, timezone

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.market_quality import excluded_domestic_reference_providers
from app.models.market import MarketQuoteRecord
from app.schemas.market import Gold18MarketContext

TROY_OUNCE_GRAMS = 31.1034768
GOLD18_PURITY = 0.75
REQUIRED_SYMBOLS = ("GOLD18", "USDT", "XAU")


class Gold18ContextError(ValueError):
    pass


class Gold18ContextService:
    """Explain Gold18 through the latest domestic, FX and global-gold data."""

    def build(self, db: Session, *, max_age_seconds: int) -> Gold18MarketContext:
        rows: dict[str, MarketQuoteRecord] = {}
        for symbol in REQUIRED_SYMBOLS:
            query = select(MarketQuoteRecord).where(MarketQuoteRecord.symbol == symbol)
            excluded = excluded_domestic_reference_providers(symbol)
            if excluded:
                query = query.where(MarketQuoteRecord.provider.not_in(excluded))
            row = db.scalar(query.order_by(MarketQuoteRecord.observed_at.desc()).limit(1))
            if row is None:
                raise Gold18ContextError(f"Missing current {symbol} reference data.")
            rows[symbol] = row

        observed_times = [_utc(row.observed_at) for row in rows.values()]
        now = datetime.now(timezone.utc)
        oldest = min(observed_times)
        newest = max(observed_times)
        if (now - oldest).total_seconds() > max_age_seconds:
            raise Gold18ContextError("Gold18 reference data is stale.")
        if (newest - oldest).total_seconds() > max_age_seconds:
            raise Gold18ContextError("Gold18 reference data is not synchronized enough.")

        gold18 = rows["GOLD18"].price
        usdt = rows["USDT"].price
        ounce = rows["XAU"].price
        implied = ounce * usdt * GOLD18_PURITY / TROY_OUNCE_GRAMS
        premium_percent = (gold18 / implied - 1.0) * 100
        premium_state = (
            "premium" if premium_percent > 1.0 else "discount" if premium_percent < -1.0 else "neutral"
        )
        return Gold18MarketContext(
            gold18_price=gold18,
            implied_gold18_price=implied,
            premium_percent=premium_percent,
            premium_state=premium_state,
            gold_ounce_price=ounce,
            tether_price=usdt,
            observed_at=oldest,
        )


def _utc(value: datetime) -> datetime:
    if value.tzinfo is None:
        return value.replace(tzinfo=timezone.utc)
    return value.astimezone(timezone.utc)
