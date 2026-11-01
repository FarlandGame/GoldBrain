from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import text
from sqlalchemy.orm import Session

from app.core.config import Settings, get_settings
from app.core.security import require_private_access
from app.schemas.system import Capability, CapabilitiesResponse, HealthResponse
from app.db.session import get_db

router = APIRouter(tags=["system"])


@router.get("/health", response_model=HealthResponse)
def health(settings: Settings = Depends(get_settings)) -> HealthResponse:
    return HealthResponse(
        status="ok",
        service=settings.app_name,
        version=settings.app_version,
        environment=settings.environment,
        timestamp=datetime.now(timezone.utc),
    )


@router.get("/ready", response_model=HealthResponse)
def ready(
    settings: Settings = Depends(get_settings),
    db: Session = Depends(get_db),
) -> HealthResponse:
    try:
        db.execute(text("SELECT 1"))
    except Exception as exc:
        raise HTTPException(status_code=503, detail="Database is unavailable.") from exc
    return HealthResponse(
        status="ready",
        service=settings.app_name,
        version=settings.app_version,
        environment=settings.environment,
        timestamp=datetime.now(timezone.utc),
    )


@router.get(
    "/capabilities",
    response_model=CapabilitiesResponse,
    dependencies=[Depends(require_private_access)],
)
def capabilities() -> CapabilitiesResponse:
    return CapabilitiesResponse(
        capabilities=[
            Capability(name="market_gateway", status="ready", phase=1, note="Live quote gateway and provider isolation."),
            Capability(name="ohlcv_history", status="ready", phase=2, note="Normalized server-side candles and quote aggregation."),
            Capability(name="forecast_v2", status="ready", phase=2, note="Auditable baseline + ML challenger ensemble."),
            Capability(name="backtesting", status="ready", phase=2, note="Chronological out-of-sample evaluation and metrics."),
            Capability(name="paper_trading", status="ready", phase=2, note="Long-only private-alpha simulator; no real-money execution."),
            Capability(name="user_auth", status="ready", phase=3, note="Argon2id users, JWT/refresh sessions and device revocation."),
            Capability(name="alerts_entitlements", status="ready", phase=3, note="User alerts and subscription entitlement interfaces."),
            Capability(name="exchange_trading", status="gated", phase=3, note="Only sandbox adapter contract; real-money execution remains disabled."),
        ]
    )
