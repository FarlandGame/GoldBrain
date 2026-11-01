from __future__ import annotations

from datetime import datetime

from app.schemas.common import ApiModel


class CreateAlertRequest(ApiModel):
    symbol: str
    condition: str
    threshold: float


class AlertRule(ApiModel):
    alert_id: str
    symbol: str
    condition: str
    threshold: float
    enabled: bool
    last_triggered_at: datetime | None
    created_at: datetime


class Entitlement(ApiModel):
    plan: str
    status: str
    starts_at: datetime
    ends_at: datetime | None
    features: list[str]


class ExchangeCapabilities(ApiModel):
    real_money_enabled: bool
    adapters: list[str]
    note: str
