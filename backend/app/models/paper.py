from __future__ import annotations

from datetime import datetime, timezone

from sqlalchemy import DateTime, ForeignKey, Index, Numeric, String, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base


class PaperAccountRecord(Base):
    __tablename__ = "paper_accounts"

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    account_key: Mapped[str] = mapped_column(String(64), unique=True, index=True)
    name: Mapped[str] = mapped_column(String(80))
    owner_user_public_id: Mapped[str | None] = mapped_column(
        String(36), ForeignKey("users.public_id"), nullable=True, index=True
    )
    base_currency: Mapped[str] = mapped_column(String(12), default="USDT")
    initial_balance: Mapped[float] = mapped_column(Numeric(38, 18, asdecimal=False))
    cash_balance: Mapped[float] = mapped_column(Numeric(38, 18, asdecimal=False))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))


class PaperPositionRecord(Base):
    __tablename__ = "paper_positions"
    __table_args__ = (UniqueConstraint("account_key", "symbol", name="uq_paper_position_account_symbol"),)

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    account_key: Mapped[str] = mapped_column(String(64), index=True)
    symbol: Mapped[str] = mapped_column(String(24), index=True)
    quantity: Mapped[float] = mapped_column(Numeric(38, 18, asdecimal=False))
    average_entry_price: Mapped[float] = mapped_column(Numeric(38, 18, asdecimal=False))
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))


class PaperTradeRecord(Base):
    __tablename__ = "paper_trades"
    __table_args__ = (Index("ix_paper_trade_account_time", "account_key", "executed_at"),)

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    trade_id: Mapped[str] = mapped_column(String(96), unique=True, index=True)
    account_key: Mapped[str] = mapped_column(String(64), index=True)
    symbol: Mapped[str] = mapped_column(String(24), index=True)
    side: Mapped[str] = mapped_column(String(8))
    quantity: Mapped[float] = mapped_column(Numeric(38, 18, asdecimal=False))
    price: Mapped[float] = mapped_column(Numeric(38, 18, asdecimal=False))
    notional: Mapped[float] = mapped_column(Numeric(38, 18, asdecimal=False))
    fee: Mapped[float] = mapped_column(Numeric(38, 18, asdecimal=False), default=0.0)
    realized_pnl: Mapped[float] = mapped_column(Numeric(38, 18, asdecimal=False), default=0.0)
    reason: Mapped[str | None] = mapped_column(String(240), nullable=True)
    forecast_id: Mapped[str | None] = mapped_column(String(96), nullable=True)
    executed_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), index=True)
