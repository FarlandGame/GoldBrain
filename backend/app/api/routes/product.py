from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, Response
from sqlalchemy.orm import Session

from app.api.dependencies import get_identity, get_market_service
from app.db.session import get_db
from app.schemas.product import AlertRule, CreateAlertRequest, Entitlement
from app.schemas.watchlist import (
    PreferencesRequest,
    PreferencesResponse,
    WatchlistItem,
    WatchlistRequest,
    WatchlistResponse,
)
from app.services.auth import Identity
from app.services.market_data import MarketDataService
from app.services.product import ProductError, ProductService

router = APIRouter(tags=["product"])
service = ProductService()


@router.get("/watchlist", response_model=WatchlistResponse)
def watchlist(identity: Identity = Depends(get_identity), db: Session = Depends(get_db)) -> WatchlistResponse:
    return service.watchlist(db, identity.user.public_id)


@router.post("/watchlist", response_model=WatchlistItem, status_code=201)
def add_watchlist(
    payload: WatchlistRequest,
    identity: Identity = Depends(get_identity),
    db: Session = Depends(get_db),
) -> WatchlistItem:
    try:
        return service.add_watchlist(db, user_public_id=identity.user.public_id, symbol=payload.symbol)
    except ProductError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc


@router.delete("/watchlist/{symbol}", status_code=204)
def remove_watchlist(
    symbol: str,
    identity: Identity = Depends(get_identity),
    db: Session = Depends(get_db),
) -> Response:
    if not service.remove_watchlist(db, user_public_id=identity.user.public_id, symbol=symbol):
        raise HTTPException(status_code=404, detail="Watchlist item not found")
    return Response(status_code=204)


@router.get("/preferences", response_model=PreferencesResponse)
def preferences(identity: Identity = Depends(get_identity), db: Session = Depends(get_db)) -> PreferencesResponse:
    return service.preferences(db, identity.user.public_id)


@router.put("/preferences", response_model=PreferencesResponse)
def update_preferences(
    payload: PreferencesRequest,
    identity: Identity = Depends(get_identity),
    db: Session = Depends(get_db),
) -> PreferencesResponse:
    return service.update_preferences(db, user_public_id=identity.user.public_id, values=payload.preferences)


@router.get("/entitlements/me", response_model=Entitlement)
def entitlement(
    identity: Identity = Depends(get_identity),
    db: Session = Depends(get_db),
) -> Entitlement:
    return service.entitlement(db, identity.user.public_id)


@router.get("/alerts", response_model=list[AlertRule])
def alerts(
    identity: Identity = Depends(get_identity),
    db: Session = Depends(get_db),
) -> list[AlertRule]:
    return service.alerts(db, identity.user.public_id)


@router.post("/alerts", response_model=AlertRule, status_code=201)
def create_alert(
    payload: CreateAlertRequest,
    identity: Identity = Depends(get_identity),
    db: Session = Depends(get_db),
) -> AlertRule:
    try:
        return service.create_alert(
            db,
            user_public_id=identity.user.public_id,
            symbol=payload.symbol,
            condition=payload.condition,
            threshold=payload.threshold,
        )
    except ProductError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc


@router.delete("/alerts/{alert_id}", status_code=204)
def delete_alert(
    alert_id: str,
    identity: Identity = Depends(get_identity),
    db: Session = Depends(get_db),
) -> Response:
    if not service.delete_alert(db, user_public_id=identity.user.public_id, alert_id=alert_id):
        raise HTTPException(status_code=404, detail="Alert not found")
    return Response(status_code=204)


@router.post("/alerts/evaluate", response_model=list[AlertRule])
async def evaluate_alerts(
    identity: Identity = Depends(get_identity),
    db: Session = Depends(get_db),
    market: MarketDataService = Depends(get_market_service),
) -> list[AlertRule]:
    rules = service.alerts(db, identity.user.public_id)
    if not rules:
        return []
    symbols = sorted({rule.symbol for rule in rules if rule.enabled})
    batch = await market.fetch_quotes(symbols)
    prices = {symbol: quote.price for symbol, quote in batch.quotes.items()}
    return service.evaluate_alerts(db, user_public_id=identity.user.public_id, prices=prices)
