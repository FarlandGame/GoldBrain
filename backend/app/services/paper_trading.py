from __future__ import annotations

from datetime import datetime, timezone
from uuid import uuid4

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models.paper import PaperAccountRecord, PaperPositionRecord, PaperTradeRecord
from app.schemas.paper import (
    CreatePaperAccountRequest,
    PaperAccount,
    PaperOrderRequest,
    PaperPortfolioResponse,
    PaperPosition,
    PaperTrade,
)


class PaperTradingError(ValueError):
    pass


class PaperTradingService:
    """Long-only spot simulator used before any real exchange integration."""

    def create_account(
        self,
        db: Session,
        request: CreatePaperAccountRequest,
        *,
        owner_user_public_id: str | None = None,
    ) -> PaperAccount:
        key = request.account_key.strip().lower()
        name = request.name.strip()
        base = request.base_currency.strip().upper()
        if not key or len(key) > 64 or not name:
            raise PaperTradingError("account_key and name are required")
        if request.initial_balance <= 0:
            raise PaperTradingError("initial_balance must be positive")
        existing = db.scalar(select(PaperAccountRecord).where(PaperAccountRecord.account_key == key))
        if existing is not None:
            raise PaperTradingError("Paper account already exists")
        row = PaperAccountRecord(
            account_key=key,
            name=name,
            owner_user_public_id=owner_user_public_id,
            base_currency=base,
            initial_balance=request.initial_balance,
            cash_balance=request.initial_balance,
            created_at=datetime.now(timezone.utc),
        )
        db.add(row)
        db.commit()
        db.refresh(row)
        return self._account_schema(row)

    def execute(
        self,
        db: Session,
        request: PaperOrderRequest,
        *,
        expected_owner_user_public_id: str | None = None,
    ) -> PaperTrade:
        account_key = request.account_key.strip().lower()
        symbol = request.symbol.strip().upper()
        side = request.side.strip().lower()
        if side not in {"buy", "sell"}:
            raise PaperTradingError("side must be buy or sell")
        if request.quantity <= 0 or request.price <= 0:
            raise PaperTradingError("quantity and price must be positive")
        if request.fee_rate < 0 or request.fee_rate > 0.05:
            raise PaperTradingError("fee_rate must be between 0 and 0.05")
        account = db.scalar(select(PaperAccountRecord).where(PaperAccountRecord.account_key == account_key))
        if account is None:
            raise PaperTradingError("Paper account not found")
        if (
            expected_owner_user_public_id is not None
            and account.owner_user_public_id != expected_owner_user_public_id
        ):
            raise PaperTradingError("Paper account is not owned by this user")
        position = db.scalar(
            select(PaperPositionRecord).where(
                PaperPositionRecord.account_key == account_key,
                PaperPositionRecord.symbol == symbol,
            )
        )
        notional = request.quantity * request.price
        fee = notional * request.fee_rate
        realized_pnl = 0.0
        now = datetime.now(timezone.utc)
        if side == "buy":
            total_cost = notional + fee
            if total_cost > account.cash_balance + 1e-9:
                raise PaperTradingError("Insufficient paper cash balance")
            old_qty = 0.0 if position is None else position.quantity
            old_avg = 0.0 if position is None else position.average_entry_price
            new_qty = old_qty + request.quantity
            new_avg = ((old_qty * old_avg) + notional) / new_qty
            account.cash_balance -= total_cost
            if position is None:
                position = PaperPositionRecord(
                    account_key=account_key,
                    symbol=symbol,
                    quantity=new_qty,
                    average_entry_price=new_avg,
                    updated_at=now,
                )
                db.add(position)
            else:
                position.quantity = new_qty
                position.average_entry_price = new_avg
                position.updated_at = now
        else:
            if position is None or request.quantity > position.quantity + 1e-9:
                raise PaperTradingError("Insufficient paper position")
            realized_pnl = (request.price - position.average_entry_price) * request.quantity - fee
            account.cash_balance += notional - fee
            position.quantity -= request.quantity
            position.updated_at = now
            if position.quantity <= 1e-12:
                db.delete(position)
        trade = PaperTradeRecord(
            trade_id=f"paper-{uuid4().hex}",
            account_key=account_key,
            symbol=symbol,
            side=side,
            quantity=request.quantity,
            price=request.price,
            notional=notional,
            fee=fee,
            realized_pnl=realized_pnl,
            reason=request.reason.strip()[:240] if request.reason else None,
            forecast_id=request.forecast_id.strip()[:96] if request.forecast_id else None,
            executed_at=now,
        )
        db.add(trade)
        db.commit()
        db.refresh(trade)
        return self._trade_schema(trade)

    def portfolio(
        self,
        db: Session,
        account_key: str,
        *,
        expected_owner_user_public_id: str | None = None,
    ) -> PaperPortfolioResponse:
        key = account_key.strip().lower()
        account = db.scalar(select(PaperAccountRecord).where(PaperAccountRecord.account_key == key))
        if account is None:
            raise PaperTradingError("Paper account not found")
        if (
            expected_owner_user_public_id is not None
            and account.owner_user_public_id != expected_owner_user_public_id
        ):
            raise PaperTradingError("Paper account is not owned by this user")
        positions = list(
            db.scalars(
                select(PaperPositionRecord)
                .where(PaperPositionRecord.account_key == key)
                .order_by(PaperPositionRecord.symbol)
            )
        )
        trades = list(
            db.scalars(
                select(PaperTradeRecord)
                .where(PaperTradeRecord.account_key == key)
                .order_by(PaperTradeRecord.executed_at.desc())
                .limit(100)
            )
        )
        return PaperPortfolioResponse(
            account=self._account_schema(account),
            positions=[
                PaperPosition(
                    symbol=item.symbol,
                    quantity=item.quantity,
                    average_entry_price=item.average_entry_price,
                )
                for item in positions
            ],
            recent_trades=[self._trade_schema(item) for item in trades],
        )

    @staticmethod
    def _account_schema(row: PaperAccountRecord) -> PaperAccount:
        return PaperAccount(
            account_key=row.account_key,
            name=row.name,
            base_currency=row.base_currency,
            initial_balance=row.initial_balance,
            cash_balance=row.cash_balance,
            created_at=_utc(row.created_at),
        )

    @staticmethod
    def _trade_schema(row: PaperTradeRecord) -> PaperTrade:
        return PaperTrade(
            trade_id=row.trade_id,
            account_key=row.account_key,
            symbol=row.symbol,
            side=row.side,
            quantity=row.quantity,
            price=row.price,
            notional=row.notional,
            fee=row.fee,
            realized_pnl=row.realized_pnl,
            reason=row.reason,
            forecast_id=row.forecast_id,
            executed_at=_utc(row.executed_at),
        )


def _utc(value: datetime) -> datetime:
    if value.tzinfo is None:
        return value.replace(tzinfo=timezone.utc)
    return value.astimezone(timezone.utc)
