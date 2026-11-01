from __future__ import annotations

from datetime import datetime

from app.schemas.common import ApiModel


class RegisterRequest(ApiModel):
    email: str
    password: str
    display_name: str
    device_name: str = "GoldBrain client"


class LoginRequest(ApiModel):
    email: str
    password: str
    device_name: str = "GoldBrain client"


class RefreshRequest(ApiModel):
    refresh_token: str


class LogoutRequest(ApiModel):
    refresh_token: str | None = None


class PasswordResetRequest(ApiModel):
    email: str


class PasswordResetConfirm(ApiModel):
    email: str
    code: str
    new_password: str


class EmailVerificationRequest(ApiModel):
    email: str


class EmailVerificationConfirm(ApiModel):
    email: str
    code: str
    new_password: str
    device_name: str = "GoldBrain client"


class RegistrationPending(ApiModel):
    email: str
    verification_required: bool = True
    expires_in: int = 900
    resend_after: int = 60


class EmailVerificationAccepted(ApiModel):
    accepted: bool = True
    email: str
    expires_in: int = 900
    resend_after: int = 60


class UserProfile(ApiModel):
    public_id: str
    email: str
    display_name: str
    role: str
    email_verified: bool
    mfa_enabled: bool
    created_at: datetime


class AuthTokens(ApiModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    expires_in_seconds: int
    session_id: str
    user: UserProfile


class SessionInfo(ApiModel):
    session_id: str
    device_name: str
    created_at: datetime
    last_seen_at: datetime
    expires_at: datetime
    current: bool = False


class PasswordResetAccepted(ApiModel):
    accepted: bool = True
    expires_in: int = 900
    resend_after: int = 60
