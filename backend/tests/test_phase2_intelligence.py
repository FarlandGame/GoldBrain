import math
from datetime import datetime, timedelta, timezone

from sqlalchemy import create_engine, func, select
from sqlalchemy.orm import Session
from sqlalchemy.pool import StaticPool

from app.db.base import Base
from app.models.forecast import ForecastRecord
from app.schemas.history import MarketCandle
from app.schemas.paper import CreatePaperAccountRequest, PaperOrderRequest
from app.services.forecasting import ForecastService
from app.services.history import MarketHistoryService
from app.services.paper_trading import PaperTradingService


def _session() -> Session:
    engine = create_engine(
        "sqlite://",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    Base.metadata.create_all(engine)
    return Session(engine)


def _candles(count: int = 320) -> list[MarketCandle]:
    start = datetime(2026, 1, 1, tzinfo=timezone.utc)
    output: list[MarketCandle] = []
    price = 100.0
    for index in range(count):
        # Smooth trend + repeating micro-cycle gives the model nontrivial but
        # deterministic history without random test flakes.
        move = 0.0012 + math.sin(index / 8.0) * 0.0018
        close = price * (1 + move)
        high = max(price, close) * 1.001
        low = min(price, close) * 0.999
        opened = start + timedelta(hours=index)
        output.append(
            MarketCandle(
                symbol="BTC",
                timeframe="1h",
                currency="USDT",
                provider="fixture",
                upstream_source="test",
                opened_at=opened,
                closed_at=opened + timedelta(hours=1),
                open=price,
                high=high,
                low=low,
                close=close,
                volume=1000 + index,
            )
        )
        price = close
    return output


def test_history_forecast_and_backtest_pipeline() -> None:
    db = _session()
    history = MarketHistoryService()
    result = history.upsert_candles(db, _candles())
    assert result.inserted == 320
    assert result.rejected == 0

    forecast_service = ForecastService(history)
    forecast = forecast_service.generate(
        db,
        symbol="BTC",
        horizon="1h",
        timeframe="1h",
        now=datetime(2026, 1, 10, tzinfo=timezone.utc),
    )
    assert forecast.symbol == "BTC"
    assert forecast.lower_bound < forecast.point_estimate < forecast.upper_bound
    assert 0.0 < forecast.probability_up < 1.0
    assert forecast.data_quality >= 70
    assert forecast.model_breakdown["validation_samples"] >= 10
    assert forecast.signal in {"buy", "sell", "no_trade"}
    assert forecast.trade_allowed is False
    assert forecast.decision_reasons

    persisted = forecast_service.latest(db, symbol="BTC", horizon="1h", timeframe="1h")
    assert persisted.forecast_id == forecast.forecast_id
    assert persisted.decision_reasons == forecast.decision_reasons
    assert persisted.reasons == forecast.reasons
    assert persisted.model_breakdown == forecast.model_breakdown

    evaluated, expired, pending = forecast_service.evaluate_due(
        db, now=datetime(2026, 1, 10, 3, tzinfo=timezone.utc)
    )
    assert evaluated == 1
    assert expired == 0
    assert pending == 0

    backtest = forecast_service.backtest(
        db,
        symbol="BTC",
        horizon="1h",
        timeframe="1h",
        minimum_train_points=80,
        max_steps=60,
    )
    assert backtest.sample_count > 10
    assert backtest.mean_absolute_percentage_error is not None
    assert backtest.baseline_mean_absolute_percentage_error is not None
    assert backtest.directional_hit_rate is not None


def test_invalid_candle_is_rejected() -> None:
    db = _session()
    history = MarketHistoryService()
    candle = _candles(1)[0].model_copy(update={"high": 1.0})
    result = history.upsert_candles(db, [candle])
    assert result.rejected == 1
    assert result.inserted == 0


def test_forecast_generation_deduplicates_unchanged_evidence() -> None:
    db = _session()
    history = MarketHistoryService()
    history.upsert_candles(db, _candles())
    service = ForecastService(history)

    first = service.generate(db, symbol="BTC", horizon="1h", timeframe="1h")
    second = service.generate(db, symbol="BTC", horizon="1h", timeframe="1h")

    assert second.forecast_id == first.forecast_id
    assert db.scalar(select(func.count()).select_from(ForecastRecord)) == 1


def test_legacy_persisted_forecast_is_explicitly_marked() -> None:
    db = _session()
    history = MarketHistoryService()
    history.upsert_candles(db, _candles())
    forecast = ForecastService(history).generate(db, symbol="BTC", horizon="1h", timeframe="1h")
    row = db.scalar(select(ForecastRecord).where(ForecastRecord.forecast_id == forecast.forecast_id))
    assert row is not None
    row.decision_reasons = None
    row.reasons = None
    row.model_breakdown = None
    db.commit()

    restored = ForecastService(history).latest(db, symbol="BTC", horizon="1h", timeframe="1h")

    assert "legacy forecast" in restored.decision_reasons[0]
    assert restored.model_breakdown["explanation_status"] == "legacy-unavailable"


def test_paper_trading_buy_and_sell_is_long_only() -> None:
    db = _session()
    service = PaperTradingService()
    account = service.create_account(
        db,
        CreatePaperAccountRequest(account_key="ali", name="Ali", initial_balance=1000),
    )
    assert account.cash_balance == 1000

    buy = service.execute(
        db,
        PaperOrderRequest(
            account_key="ali",
            symbol="BTC",
            side="buy",
            quantity=2,
            price=100,
            fee_rate=0.001,
            reason="private alpha test",
        ),
    )
    assert buy.side == "buy"
    portfolio = service.portfolio(db, "ali")
    assert portfolio.positions[0].quantity == 2
    assert portfolio.account.cash_balance < 800

    sell = service.execute(
        db,
        PaperOrderRequest(
            account_key="ali",
            symbol="BTC",
            side="sell",
            quantity=1,
            price=110,
            fee_rate=0.001,
        ),
    )
    assert sell.realized_pnl > 0
    portfolio = service.portfolio(db, "ali")
    assert portfolio.positions[0].quantity == 1
