from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.api.dependencies import get_identity
from app.db.session import get_db
from app.schemas.paper import (
    CreatePaperAccountRequest,
    PaperAccount,
    PaperOrderRequest,
    PaperPortfolioResponse,
    PaperTrade,
)
from app.services.auth import Identity
from app.services.paper_trading import PaperTradingError, PaperTradingService

router = APIRouter(prefix="/paper", tags=["paper-trading"])
service = PaperTradingService()


@router.post("/accounts", response_model=PaperAccount)
def create_account(
    payload: CreatePaperAccountRequest,
    identity: Identity = Depends(get_identity),
    db: Session = Depends(get_db),
) -> PaperAccount:
    scoped = payload.model_copy(update={"account_key": identity.user.public_id})
    try:
        return service.create_account(
            db,
            scoped,
            owner_user_public_id=identity.user.public_id,
        )
    except PaperTradingError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc


@router.post("/orders", response_model=PaperTrade)
def order(
    payload: PaperOrderRequest,
    identity: Identity = Depends(get_identity),
    db: Session = Depends(get_db),
) -> PaperTrade:
    scoped = payload.model_copy(update={"account_key": identity.user.public_id})
    try:
        return service.execute(
            db,
            scoped,
            expected_owner_user_public_id=identity.user.public_id,
        )
    except PaperTradingError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc


@router.get("/portfolio/me", response_model=PaperPortfolioResponse)
def my_portfolio(
    identity: Identity = Depends(get_identity),
    db: Session = Depends(get_db),
) -> PaperPortfolioResponse:
    try:
        return service.portfolio(
            db,
            identity.user.public_id,
            expected_owner_user_public_id=identity.user.public_id,
        )
    except PaperTradingError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
