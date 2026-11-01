from __future__ import annotations

import hashlib
from typing import Annotated

from fastapi import APIRouter, Body, Depends, Header, HTTPException, Response, status
from sqlalchemy.orm import Session

from app.api.dependencies import get_identity
from app.core.config import Settings, get_settings
from app.db.session import get_db
from app.schemas.auth import (
    AuthTokens,
    EmailVerificationAccepted,
    EmailVerificationConfirm,
    EmailVerificationRequest,
    LoginRequest,
    LogoutRequest,
    PasswordResetAccepted,
    PasswordResetConfirm,
    PasswordResetRequest,
    RefreshRequest,
    RegisterRequest,
    RegistrationPending,
    SessionInfo,
    UserProfile,
)
from app.services.auth import AuthError, AuthService, Identity
from app.services.auth_email import AuthEmailSender

router = APIRouter(prefix="/auth", tags=["auth"])


def get_auth_email_sender(settings: Settings = Depends(get_settings)) -> AuthEmailSender:
    return AuthEmailSender(settings)


def _http_error(exc: AuthError, default_status: int = 422) -> HTTPException:
    return HTTPException(
        status_code=exc.status_code or default_status,
        detail={"code": exc.code, "message": str(exc)},
        headers={"Retry-After": str(exc.retry_after)} if exc.retry_after is not None else None,
    )


def _fingerprint(value: str | None) -> str | None:
    if not value or not value.strip():
        return None
    return hashlib.sha256(value.strip().encode()).hexdigest()


@router.post("/register", response_model=RegistrationPending, status_code=201)
def register(
    payload: RegisterRequest,
    x_device_fingerprint: Annotated[str | None, Header(alias="X-Device-Fingerprint")] = None,
    db: Session = Depends(get_db),
    settings: Settings = Depends(get_settings),
    email_sender: AuthEmailSender = Depends(get_auth_email_sender),
) -> RegistrationPending:
    try:
        return AuthService(settings, email_sender=email_sender).register(
            db,
            email=payload.email,
            password=payload.password,
            display_name=payload.display_name,
            device_name=payload.device_name,
            fingerprint=_fingerprint(x_device_fingerprint),
        )
    except AuthError as exc:
        raise _http_error(exc) from exc


@router.post("/email-verification/request", response_model=EmailVerificationAccepted)
def email_verification_request(
    payload: EmailVerificationRequest,
    db: Session = Depends(get_db),
    settings: Settings = Depends(get_settings),
    email_sender: AuthEmailSender = Depends(get_auth_email_sender),
) -> EmailVerificationAccepted:
    try:
        AuthService(settings, email_sender=email_sender).request_email_verification(db, payload.email)
    except AuthError as exc:
        raise _http_error(exc) from exc
    return EmailVerificationAccepted(email=payload.email.strip().lower())


@router.post("/email-verification/confirm", response_model=AuthTokens)
def email_verification_confirm(
    payload: EmailVerificationConfirm,
    x_device_fingerprint: Annotated[str | None, Header(alias="X-Device-Fingerprint")] = None,
    db: Session = Depends(get_db),
    settings: Settings = Depends(get_settings),
) -> AuthTokens:
    try:
        return AuthService(settings).confirm_email_verification(
            db, email=payload.email, code=payload.code, new_password=payload.new_password, device_name=payload.device_name,
            fingerprint=_fingerprint(x_device_fingerprint),
        )
    except AuthError as exc:
        raise _http_error(exc) from exc


@router.post("/login", response_model=AuthTokens)
def login(
    payload: LoginRequest,
    x_device_fingerprint: Annotated[str | None, Header(alias="X-Device-Fingerprint")] = None,
    db: Session = Depends(get_db),
    settings: Settings = Depends(get_settings),
) -> AuthTokens:
    try:
        return AuthService(settings).login(
            db,
            email=payload.email,
            password=payload.password,
            device_name=payload.device_name,
            fingerprint=_fingerprint(x_device_fingerprint),
        )
    except AuthError as exc:
        raise _http_error(exc, status.HTTP_401_UNAUTHORIZED) from exc


@router.post("/refresh", response_model=AuthTokens)
def refresh(
    payload: RefreshRequest,
    db: Session = Depends(get_db),
    settings: Settings = Depends(get_settings),
) -> AuthTokens:
    try:
        return AuthService(settings).refresh(db, payload.refresh_token)
    except AuthError as exc:
        raise _http_error(exc, status.HTTP_401_UNAUTHORIZED) from exc


@router.get("/me", response_model=UserProfile)
def me(identity: Identity = Depends(get_identity)) -> UserProfile:
    return AuthService.profile(identity.user)


@router.get("/sessions", response_model=list[SessionInfo])
def sessions(
    identity: Identity = Depends(get_identity),
    db: Session = Depends(get_db),
    settings: Settings = Depends(get_settings),
) -> list[SessionInfo]:
    return AuthService(settings).list_sessions(
        db,
        user_public_id=identity.user.public_id,
        current_session_id=identity.session.session_id,
    )


@router.delete("/sessions/{session_id}", status_code=204)
def revoke_session(
    session_id: str,
    identity: Identity = Depends(get_identity),
    db: Session = Depends(get_db),
    settings: Settings = Depends(get_settings),
) -> Response:
    found = AuthService(settings).revoke_session(
        db,
        user_public_id=identity.user.public_id,
        session_id=session_id,
    )
    if not found:
        raise HTTPException(status_code=404, detail="Session not found")
    return Response(status_code=204)


@router.post("/logout", status_code=204)
def logout(
    payload: LogoutRequest | None = Body(default=None),
    authorization: Annotated[str | None, Header(alias="Authorization")] = None,
    db: Session = Depends(get_db),
    settings: Settings = Depends(get_settings),
) -> Response:
    service = AuthService(settings)
    value = (authorization or "").strip()
    if value.lower().startswith("bearer "):
        try:
            identity = service.resolve_identity(db, value[7:].strip())
        except AuthError as exc:
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail=str(exc)) from exc
        service.revoke_session(db, user_public_id=identity.user.public_id, session_id=identity.session.session_id)
        return Response(status_code=204)
    if payload is not None and payload.refresh_token and service.revoke_refresh_token(db, payload.refresh_token):
        return Response(status_code=204)
    raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Authentication required.")


@router.post("/logout-all", status_code=204)
def logout_all(
    identity: Identity = Depends(get_identity),
    db: Session = Depends(get_db),
    settings: Settings = Depends(get_settings),
) -> Response:
    AuthService(settings).revoke_all_sessions(db, user_public_id=identity.user.public_id)
    return Response(status_code=204)


@router.post("/password-reset/request", response_model=PasswordResetAccepted)
def password_reset_request(
    payload: PasswordResetRequest,
    db: Session = Depends(get_db),
    settings: Settings = Depends(get_settings),
    email_sender: AuthEmailSender = Depends(get_auth_email_sender),
) -> PasswordResetAccepted:
    try:
        AuthService(settings, email_sender=email_sender).create_password_reset(db, payload.email)
    except AuthError as exc:
        raise _http_error(exc) from exc
    return PasswordResetAccepted()


@router.post("/password-reset/confirm", status_code=204)
def password_reset_confirm(
    payload: PasswordResetConfirm,
    db: Session = Depends(get_db),
    settings: Settings = Depends(get_settings),
) -> Response:
    try:
        AuthService(settings).confirm_password_reset(
            db,
            email=payload.email,
            code=payload.code,
            new_password=payload.new_password,
        )
    except AuthError as exc:
        raise _http_error(exc) from exc
    return Response(status_code=204)
