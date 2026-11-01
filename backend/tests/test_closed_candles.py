from datetime import datetime, timedelta, timezone

from sqlalchemy import create_engine
from sqlalchemy.orm import Session

from app.db.base import Base
from app.models.market import MarketQuoteRecord
from app.services.history import MarketHistoryService


def test_quote_aggregation_and_history_exclude_open_candles() -> None:
    engine = create_engine("sqlite://")
    Base.metadata.create_all(engine)
    db = Session(engine)
    cutoff = datetime(2026, 1, 1, 10, 30, tzinfo=timezone.utc)
    db.add_all(
        [
            MarketQuoteRecord(
                symbol="GOLD18",
                price=20_000_000,
                currency="IRT",
                provider="test",
                observed_at=cutoff - timedelta(minutes=45),
                unit="gram_18k",
                market="IRAN",
            ),
            MarketQuoteRecord(
                symbol="GOLD18",
                price=20_100_000,
                currency="IRT",
                provider="test",
                observed_at=cutoff - timedelta(minutes=5),
                unit="gram_18k",
                market="IRAN",
            ),
        ]
    )
    db.commit()

    history = MarketHistoryService()
    result = history.build_quote_candles(
        db,
        symbol="GOLD18",
        timeframe="1h",
        lookback_hours=2,
        now=cutoff,
    )
    candles = history.get_candles(
        db,
        "GOLD18",
        "1h",
        closed_before=cutoff,
    )

    assert result.inserted == 1
    assert len(candles) == 1
    assert candles[0].opened_at.replace(tzinfo=timezone.utc) == datetime(
        2026, 1, 1, 9, tzinfo=timezone.utc
    )
    assert candles[0].close == 20_000_000
