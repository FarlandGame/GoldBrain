from __future__ import annotations

from datetime import datetime, timezone

from sqlalchemy import Boolean, DateTime, ForeignKey, Index, Integer, String, Text, text
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base


class UserRecord(Base):
    __tablename__ = "users"

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    public_id: Mapped[str] = mapped_column(String(36), unique=True, index=True)
    email: Mapped[str] = mapped_column(String(320), unique=True, index=True)
    display_name: Mapped[str] = mapped_column(String(100))
    password_hash: Mapped[str] = mapped_column(String(500))
    role: Mapped[str] = mapped_column(String(24), default="user")
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    email_verified: Mapped[bool] = mapped_column(Boolean, default=False)
    email_verification_required: Mapped[bool] = mapped_column(Boolean, default=False, server_default=text("false"))
    mfa_enabled: Mapped[bool] = mapped_column(Boolean, default=False)
    mfa_secret_encrypted: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc)
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc)
    )


class SessionRecord(Base):
    __tablename__ = "user_sessions"
    __table_args__ = (Index("ix_user_session_user_active", "user_public_id", "revoked_at"),)

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    session_id: Mapped[str] = mapped_column(String(36), unique=True, index=True)
    user_public_id: Mapped[str] = mapped_column(String(36), ForeignKey("users.public_id"), index=True)
    refresh_token_hash: Mapped[str] = mapped_column(String(64), unique=True, index=True)
    device_name: Mapped[str] = mapped_column(String(160), default="Unknown device")
    client_fingerprint: Mapped[str | None] = mapped_column(String(64), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    last_seen_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), index=True)
    revoked_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)


class AccountTokenRecord(Base):
    __tablename__ = "account_tokens"
    __table_args__ = (
        Index("ix_account_token_user_purpose", "user_public_id", "purpose"),
        Index(
            "uq_account_token_pending_code", "user_public_id", "purpose", unique=True,
            sqlite_where=text("used_at IS NULL AND purpose IN ('email_verification', 'password_reset')"),
            postgresql_where=text("used_at IS NULL AND purpose IN ('email_verification', 'password_reset')"),
        ),
    )

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    token_hash: Mapped[str] = mapped_column(String(64), unique=True, index=True)
    user_public_id: Mapped[str] = mapped_column(String(36), ForeignKey("users.public_id"), index=True)
    purpose: Mapped[str] = mapped_column(String(32))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), index=True)
    used_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    challenge_id: Mapped[str | None] = mapped_column(String(36), nullable=True)
    attempt_count: Mapped[int] = mapped_column(Integer, default=0, server_default="0")
    sent_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
