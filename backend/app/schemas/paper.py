from __future__ import annotations

from datetime import datetime

from app.schemas.common import ApiModel


class CreatePaperAccountRequest(ApiModel):
    account_key: str = ""
    name: str
    initial_balance: float = 10_000.0
    base_currency: str = "USDT"


class PaperAccount(ApiModel):
    account_key: str = ""
    name: str
    base_currency: str
    initial_balance: float
    cash_balance: float
    created_at: datetime


class PaperOrderRequest(ApiModel):
    account_key: str = ""
    symbol: str
    side: str
    quantity: float
    price: float
    fee_rate: float = 0.0
    reason: str | None = None
    forecast_id: str | None = None


class PaperTrade(ApiModel):
    trade_id: str
    account_key: str = ""
    symbol: str
    side: str
    quantity: float
    price: float
    notional: float
    fee: float
    realized_pnl: float
    reason: str | None
    forecast_id: str | None
    executed_at: datetime


class PaperPosition(ApiModel):
    symbol: str
    quantity: float
    average_entry_price: float


class PaperPortfolioResponse(ApiModel):
    account: PaperAccount
    positions: list[PaperPosition]
    recent_trades: list[PaperTrade]
