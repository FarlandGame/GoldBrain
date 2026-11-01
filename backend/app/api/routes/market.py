from datetime import datetime, timezone
from typing import Annotated, cast

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import select
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.orm import Session

from app.api.dependencies import get_market_service
from app.core.config import Settings, get_settings
from app.core.security import require_client_access
from app.db.session import get_db
from app.models.market import MarketAssetRecord
from app.schemas.market import (
    AssetListResponse,
    AssetMetadata,
    DashboardOverviewResponse,
    Gold18MarketContext,
    MarketDataStatusResponse,
    MarketObservabilityResponse,
    MarketQuote,
    ProviderObservability,
    ProviderIssue,
    QuoteBatchResponse,
)
from app.services.gold18_context import Gold18ContextError, Gold18ContextService
from app.services.history import MarketHistoryService
from app.services.market_data import SUPPORTED_ASSETS, MarketDataService
from app.services.market_overview import MarketOverviewService
from app.services.market_status import MarketStatusService
from app.services.observability import MarketObservabilityService

router = APIRouter(
    prefix="/market",
    tags=["market"],
    dependencies=[Depends(require_client_access)],
)


@router.get("/assets", response_model=AssetListResponse)
def assets(db: Session = Depends(get_db)) -> AssetListResponse:
    try:
        rows = list(db.scalars(select(MarketAssetRecord).order_by(MarketAssetRecord.symbol)))
    except SQLAlchemyError:
        # A pre-Phase-5 local database may not have run the new migration yet;
        # keep the compatibility asset catalogue readable until it is migrated.
        db.rollback()
        rows = []
    stored = {row.symbol: row for row in rows}
    return AssetListResponse(assets=[
        AssetMetadata(
            symbol=item.symbol,
            name=stored[item.symbol].name if item.symbol in stored else item.name,
            asset_class=item.asset_class,
            quote_currency=item.quote_currency,
            live_quote=item.live_quote,
            forecast=item.forecast,
        )
        for item in SUPPORTED_ASSETS
        if item.symbol not in stored or stored[item.symbol].enabled
    ])


@router.get("/gold18-context", response_model=Gold18MarketContext)
def gold18_context(
    db: Session = Depends(get_db),
    settings: Settings = Depends(get_settings),
) -> Gold18MarketContext:
    try:
        return Gold18ContextService().build(db, max_age_seconds=settings.market_max_quote_age_seconds)
    except Gold18ContextError as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc


@router.get("/status", response_model=MarketDataStatusResponse)
def market_status(
    db: Session = Depends(get_db),
    settings: Settings = Depends(get_settings),
) -> MarketDataStatusResponse:
    return MarketDataStatusResponse(
        assets=MarketStatusService().latest_statuses(
            db,
            symbols=("GOLD18", "USDT", "BTC"),
            max_age_seconds=settings.market_max_quote_age_seconds,
        )
    )


@router.get("/overview", response_model=DashboardOverviewResponse)
def market_overview(
    db: Session = Depends(get_db),
    settings: Settings = Depends(get_settings),
) -> DashboardOverviewResponse:
    """One persisted read model for the private-beta dashboard."""
    return DashboardOverviewResponse(
        generated_at=datetime.now(timezone.utc),
        assets=MarketOverviewService().build(
            db,
            symbols=("GOLD18", "USDT", "BTC"),
            max_age_seconds=settings.market_max_quote_age_seconds,
        ),
    )


@router.get("/observability", response_model=MarketObservabilityResponse)
def observability(
    window_minutes: int = Query(60, ge=1, le=1440),
    db: Session = Depends(get_db),
) -> MarketObservabilityResponse:
    snapshot = MarketObservabilityService().market_snapshot(db)
    providers = [
        ProviderObservability.model_validate(item)
        for item in MarketObservabilityService().summary(db, window_minutes=window_minutes)
    ]
    return MarketObservabilityResponse(
        window_minutes=window_minutes,
        providers=providers,
        market_age_seconds=cast(dict[str, int | None], snapshot.get("market_age_seconds", {})),
        last_successful_update=cast(dict[str, datetime | None], snapshot.get("last_successful_update", {})),
        fallback_usage=int(str(snapshot.get("fallback_usage", 0))),
        gap_count=int(str(snapshot.get("gap_count", 0))),
        stale_data_count=int(str(snapshot.get("stale_data_count", 0))),
    )


@router.get("/quotes", response_model=QuoteBatchResponse)
async def quotes(
    symbols: Annotated[list[str] | None, Query()] = None,
    force_refresh: bool = False,
    service: MarketDataService = Depends(get_market_service),
    db: Session = Depends(get_db),
) -> QuoteBatchResponse:
    requested = symbols or [asset.symbol for asset in SUPPORTED_ASSETS if asset.live_quote]
    batch = await service.fetch_quotes(requested, force_refresh=force_refresh)
    telemetry = service.drain_observability()
    observability_service = MarketObservabilityService()
    for item in telemetry:
        observability_service.record(
            db,
            provider=str(item.get("provider", "unknown")),
            operation=str(item.get("operation", "quotes")),
            status=str(item.get("status", "error")),
            latency_ms=(
                int(str(item["latency_ms"]))
                if isinstance(item.get("latency_ms"), (int, float, str))
                else None
            ),
            error_kind=str(item["error_kind"]) if item.get("error_kind") else None,
            fallback_used=bool(item.get("fallback_used")),
        )
    if batch.quotes:
        MarketHistoryService().persist_quotes(db, batch.quotes.values())
    available = dict(batch.quotes)
    issues = dict(batch.issues)
    for symbol in batch.requested:
        if symbol in available or symbol not in {item.symbol for item in SUPPORTED_ASSETS}:
            continue
        last_known = MarketHistoryService().latest_quote(db, symbol)
        if last_known is not None:
            available[symbol] = last_known
            issues[symbol] = f"Only stale last-known data is available for {symbol}."
    return QuoteBatchResponse(
        requested_symbols=list(batch.requested),
        quotes=[available[key] for key in batch.requested if key in available],
        issues=[ProviderIssue(symbol=key, message=value) for key, value in issues.items()],
        partial=bool(available) and len(available) < len(batch.requested),
    )


@router.get("/{asset}/quote", response_model=MarketQuote)
async def asset_quote(
    asset: str,
    force_refresh: bool = False,
    service: MarketDataService = Depends(get_market_service),
    db: Session = Depends(get_db),
) -> MarketQuote:
    symbol = asset.strip().upper()
    if symbol not in {item.symbol for item in SUPPORTED_ASSETS}:
        raise HTTPException(status_code=404, detail="Unsupported market asset")
    batch = await service.fetch_quotes((symbol,), force_refresh=force_refresh)
    quote = batch.quotes.get(symbol)
    if quote is None:
        last_known = MarketHistoryService().latest_quote(db, symbol)
        if last_known is not None:
            return last_known
        raise HTTPException(status_code=503, detail=batch.issues.get(symbol, "Market data unavailable"))
    MarketHistoryService().persist_quotes(db, (quote,))
    return quote
