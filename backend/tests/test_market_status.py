from datetime import datetime, timedelta, timezone

from sqlalchemy import create_engine
from sqlalchemy.orm import Session

from app.db.base import Base
from app.models.market import MarketQuoteRecord
from app.services.market_status import MarketStatusService


def test_market_status_distinguishes_fresh_stale_and_missing() -> None:
    engine = create_engine("sqlite://")
    Base.metadata.create_all(engine)
    db = Session(engine)
    now = datetime.now(timezone.utc)
    db.add_all([
        MarketQuoteRecord(symbol="BTC", price=65000, currency="USDT", provider="wallex", observed_at=now),
        MarketQuoteRecord(
            symbol="USDT",
            price=90000,
            currency="IRT",
            provider="wallex",
            observed_at=now - timedelta(minutes=10),
        ),
    ])
    db.commit()

    statuses = MarketStatusService().latest_statuses(
        db, symbols=("BTC", "USDT", "GOLD18"), max_age_seconds=300
    )
    by_symbol = {status.symbol: status for status in statuses}

    assert by_symbol["BTC"].status == "fresh"
    assert by_symbol["USDT"].status == "stale"
    assert by_symbol["GOLD18"].status == "missing"
