from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.core.security import require_client_access, require_private_access
from app.db.session import get_db
from app.schemas.forecast import (
    BacktestRequest,
    BacktestResponse,
    ForecastEvaluationSummary,
    ForecastMetrics,
    ForecastRequest,
    ForecastResponse,
)
from app.services.forecasting import ForecastError, ForecastService

router = APIRouter(
    prefix="/forecast",
    tags=["forecast"],
    dependencies=[Depends(require_client_access)],
)
forecasts_router = APIRouter(
    prefix="/forecasts",
    tags=["forecast"],
    dependencies=[Depends(require_client_access)],
)
performance_router = APIRouter(
    prefix="/forecast-performance",
    tags=["forecast"],
    dependencies=[Depends(require_client_access)],
)
service = ForecastService()


@router.post("", response_model=ForecastResponse)
def forecast(payload: ForecastRequest, db: Session = Depends(get_db)) -> ForecastResponse:
    try:
        return service.generate(
            db,
            symbol=payload.symbol,
            horizon=payload.horizon,
            timeframe=payload.timeframe,
            persist=payload.persist,
        )
    except ForecastError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc


@router.post(
    "/evaluate",
    response_model=ForecastEvaluationSummary,
    dependencies=[Depends(require_private_access)],
)
def evaluate(db: Session = Depends(get_db)) -> ForecastEvaluationSummary:
    evaluated, expired, pending = service.evaluate_due(db)
    return ForecastEvaluationSummary(evaluated=evaluated, expired=expired, pending=pending)


@router.get("/latest", response_model=ForecastResponse)
def latest(
    symbol: str,
    horizon: str = "1h",
    timeframe: str = "1h",
    db: Session = Depends(get_db),
) -> ForecastResponse:
    try:
        return service.latest(db, symbol=symbol, horizon=horizon, timeframe=timeframe)
    except ForecastError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc


@router.get("/metrics", response_model=ForecastMetrics)
def metrics(symbol: str, horizon: str = "1h", db: Session = Depends(get_db)) -> ForecastMetrics:
    return service.metrics(db, symbol=symbol, horizon=horizon)


@router.post("/backtest", response_model=BacktestResponse, dependencies=[Depends(require_private_access)])
def backtest(payload: BacktestRequest, db: Session = Depends(get_db)) -> BacktestResponse:
    try:
        return service.backtest(
            db,
            symbol=payload.symbol,
            horizon=payload.horizon,
            timeframe=payload.timeframe,
            minimum_train_points=payload.minimum_train_points,
            max_steps=payload.max_steps,
        )
    except ForecastError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc


@forecasts_router.post("", response_model=ForecastResponse)
def forecasts(payload: ForecastRequest, db: Session = Depends(get_db)) -> ForecastResponse:
    return forecast(payload, db)


@forecasts_router.get("/{asset}", response_model=ForecastResponse)
def asset_forecast(
    asset: str,
    horizon: str = "1h",
    timeframe: str = "1h",
    db: Session = Depends(get_db),
) -> ForecastResponse:
    return latest(asset, horizon=horizon, timeframe=timeframe, db=db)


@performance_router.get("", response_model=ForecastMetrics)
def forecast_performance(symbol: str, horizon: str = "1h", db: Session = Depends(get_db)) -> ForecastMetrics:
    return metrics(symbol=symbol, horizon=horizon, db=db)
