from __future__ import annotations

import hmac
from typing import Annotated

from fastapi import Depends, Header, HTTPException, status
from sqlalchemy.orm import Session

from app.core.config import Settings, get_settings
from app.db.session import get_db
from app.services.auth import AuthError, AuthService


def require_private_access(
    x_goldbrain_key: Annotated[str | None, Header(alias="X-GoldBrain-Key")] = None,
    settings: Settings = Depends(get_settings),
) -> None:
    expected = settings.private_api_key.strip()
    if not expected and settings.environment in {"development", "test"}:
        return
    provided = (x_goldbrain_key or "").strip()
    if not provided or not hmac.compare_digest(provided, expected):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or missing GoldBrain API key.",
        )


def require_client_access(
    authorization: Annotated[str | None, Header(alias="Authorization")] = None,
    x_goldbrain_key: Annotated[str | None, Header(alias="X-GoldBrain-Key")] = None,
    settings: Settings = Depends(get_settings),
    db: Session = Depends(get_db),
) -> None:
    """Allow either owner private key or a signed user access token."""
    expected = settings.private_api_key.strip()
    provided = (x_goldbrain_key or "").strip()
    if expected and provided and hmac.compare_digest(provided, expected):
        return
    if not expected and settings.environment in {"development", "test"} and not authorization:
        return
    value = (authorization or "").strip()
    if value.lower().startswith("bearer "):
        token = value[7:].strip()
        try:
            AuthService(settings).resolve_identity(db, token)
            return
        except AuthError:
            pass
    raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Authentication required.")
