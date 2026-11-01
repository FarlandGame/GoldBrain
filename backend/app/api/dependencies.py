from __future__ import annotations

from typing import Annotated

from fastapi import Depends, Header, HTTPException, Request, status
from sqlalchemy.orm import Session

from app.core.config import Settings, get_settings
from app.db.session import get_db
from app.services.auth import AuthError, AuthService, Identity
from app.services.market_data import MarketDataService
from app.services.news import NewsService
from app.services.country_pulse_data import CountryPulseDataService
from app.services.ai import AiNarrativeService


def get_market_service(request: Request) -> MarketDataService:
    return request.app.state.market_service


def get_news_service(request: Request) -> NewsService:
    return request.app.state.news_service


def get_country_pulse_service(request: Request) -> CountryPulseDataService:
    return request.app.state.country_pulse_service


def get_ai_service(request: Request) -> AiNarrativeService:
    return request.app.state.ai_service


def get_identity(
    authorization: Annotated[str | None, Header(alias="Authorization")] = None,
    db: Session = Depends(get_db),
    settings: Settings = Depends(get_settings),
) -> Identity:
    value = (authorization or "").strip()
    if not value.lower().startswith("bearer "):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Bearer token required.")
    token = value[7:].strip()
    try:
        return AuthService(settings).resolve_identity(db, token)
    except AuthError as exc:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail=str(exc)) from exc
