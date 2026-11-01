from __future__ import annotations

from datetime import datetime, timezone

from sqlalchemy import Boolean, DateTime, ForeignKey, Index, JSON, Numeric, String, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base


class AuditLogRecord(Base):
    __tablename__ = "audit_logs"
    __table_args__ = (Index("ix_audit_user_time", "user_public_id", "created_at"),)

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    user_public_id: Mapped[str | None] = mapped_column(String(36), nullable=True, index=True)
    action: Mapped[str] = mapped_column(String(80), index=True)
    resource: Mapped[str] = mapped_column(String(120), default="")
    outcome: Mapped[str] = mapped_column(String(24), default="success")
    metadata_json: Mapped[str] = mapped_column(String(2000), default="{}")
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc), index=True
    )


class AlertRuleRecord(Base):
    __tablename__ = "alert_rules"
    __table_args__ = (Index("ix_alert_user_enabled", "user_public_id", "enabled"),)

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    alert_id: Mapped[str] = mapped_column(String(36), unique=True, index=True)
    user_public_id: Mapped[str] = mapped_column(String(36), ForeignKey("users.public_id"), index=True)
    symbol: Mapped[str] = mapped_column(String(24), index=True)
    condition: Mapped[str] = mapped_column(String(16))
    threshold: Mapped[float] = mapped_column(Numeric(38, 12, asdecimal=False))
    enabled: Mapped[bool] = mapped_column(Boolean, default=True)
    last_triggered_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc)
    )


class EntitlementRecord(Base):
    __tablename__ = "entitlements"

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    user_public_id: Mapped[str] = mapped_column(String(36), ForeignKey("users.public_id"), unique=True, index=True)
    plan: Mapped[str] = mapped_column(String(24), default="free")
    status: Mapped[str] = mapped_column(String(24), default="active")
    starts_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    ends_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    source: Mapped[str] = mapped_column(String(40), default="private-beta")


class WatchlistRecord(Base):
    __tablename__ = "watchlists"
    __table_args__ = (UniqueConstraint("user_public_id", "symbol", name="uq_watchlist_user_symbol"),)

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    user_public_id: Mapped[str] = mapped_column(String(36), ForeignKey("users.public_id"), index=True)
    symbol: Mapped[str] = mapped_column(String(24), index=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc)
    )


class UserPreferenceRecord(Base):
    __tablename__ = "user_preferences"

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    user_public_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("users.public_id"), unique=True
    )
    preferences: Mapped[dict] = mapped_column(JSON, default=dict)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc)
    )
