from datetime import datetime, timezone

from sqlalchemy import create_engine
from sqlalchemy.orm import Session

from app.db.base import Base
from app.models.forecast import ForecastRecord
from app.models.market import MarketQuoteRecord
from app.services.market_overview import MarketOverviewService


def test_overview_uses_persisted_quote_status_and_latest_forecast() -> None:
    engine = create_engine("sqlite://")
    Base.metadata.create_all(engine)
    db = Session(engine)
    now = datetime.now(timezone.utc)
    db.add(MarketQuoteRecord(symbol="BTC", price=65000, currency="USDT", provider="wallex", observed_at=now))
    db.add(
        ForecastRecord(
            forecast_id="btc-forecast",
            symbol="BTC",
            timeframe="1h",
            horizon="1h",
            direction="up",
            anchor_price=64000,
            point_estimate=66000,
            lower_bound=65000,
            upper_bound=67000,
            confidence_score=61,
            probability_up=0.61,
            data_quality=80,
            signal="no_trade",
            signal_quality="low",
            trade_allowed=False,
            model_version="test",
            feature_version="test",
            evidence_fingerprint="test",
            calibration_status="provisional",
            generated_at=now,
            target_at=now,
        )
    )
    db.commit()

    assets = MarketOverviewService().build(
        db, symbols=("GOLD18", "USDT", "BTC"), max_age_seconds=300
    )
    by_symbol = {item.symbol: item for item in assets}

    assert by_symbol["BTC"].data_status.status == "fresh"
    assert by_symbol["BTC"].quote is not None
    assert by_symbol["BTC"].quote.price == 65000
    assert by_symbol["BTC"].forecast is not None
    assert by_symbol["BTC"].forecast.forecast_id == "btc-forecast"
    assert by_symbol["GOLD18"].data_status.status == "missing"
    assert by_symbol["GOLD18"].quote is None
    assert by_symbol["GOLD18"].forecast is None
