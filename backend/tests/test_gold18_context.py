from datetime import datetime, timedelta, timezone

import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import Session

from app.db.base import Base
from app.models.market import MarketQuoteRecord
from app.services.gold18_context import Gold18ContextError, Gold18ContextService


def _session() -> Session:
    engine = create_engine("sqlite://")
    Base.metadata.create_all(engine)
    return Session(engine)


def _quote(symbol: str, price: float, observed_at: datetime) -> MarketQuoteRecord:
    return MarketQuoteRecord(
        symbol=symbol,
        price=price,
        currency="IRT",
        provider="test",
        observed_at=observed_at,
    )


def test_gold18_context_calculates_implied_price_and_premium() -> None:
    db = _session()
    now = datetime.now(timezone.utc)
    db.add_all([
        _quote("GOLD18", 10000000, now),
        _quote("USDT", 90000, now),
        _quote("XAU", 3000, now),
    ])
    db.commit()
    context = Gold18ContextService().build(db, max_age_seconds=300)

    assert context.implied_gold18_price == pytest.approx(3000 * 90000 * 0.75 / 31.1034768)
    assert context.premium_percent > 0
    assert context.premium_state == "premium"


def test_gold18_context_rejects_stale_reference_data() -> None:
    db = _session()
    stale = datetime.now(timezone.utc) - timedelta(minutes=10)
    db.add_all([
        _quote("GOLD18", 10000000, stale),
        _quote("USDT", 90000, stale),
        _quote("XAU", 3000, stale),
    ])
    db.commit()

    with pytest.raises(Gold18ContextError, match="stale"):
        Gold18ContextService().build(db, max_age_seconds=300)


def test_gold18_context_rejects_old_persian_toolbox_reference() -> None:
    db = _session()
    now = datetime.now(timezone.utc)
    gold = _quote("GOLD18", 10_000_000, now)
    gold.provider = "persian-toolbox"
    db.add_all([gold, _quote("USDT", 90_000, now), _quote("XAU", 3_000, now)])
    db.commit()

    with pytest.raises(Gold18ContextError, match="Missing current GOLD18"):
        Gold18ContextService().build(db, max_age_seconds=300)
