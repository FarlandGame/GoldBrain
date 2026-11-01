from __future__ import annotations

from datetime import datetime, timezone
from uuid import uuid4

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models.product import (
    AlertRuleRecord,
    EntitlementRecord,
    UserPreferenceRecord,
    WatchlistRecord,
)
from app.schemas.product import AlertRule, Entitlement
from app.schemas.watchlist import PreferencesResponse, WatchlistItem, WatchlistResponse
from app.services.audit import AuditService
from app.services.market_data import SUPPORTED_SYMBOLS


PLAN_FEATURES = {
    "free": ["limited_market", "limited_forecast"],
    "pro": ["market", "forecast", "deep_analysis", "alerts", "paper_trading"],
    "owner": ["market", "forecast", "deep_analysis", "alerts", "paper_trading", "developer_tools"],
}


class ProductError(ValueError):
    pass


class ProductService:
    def __init__(self) -> None:
        self.audit = AuditService()

    def entitlement(self, db: Session, user_public_id: str) -> Entitlement:
        row = db.scalar(select(EntitlementRecord).where(EntitlementRecord.user_public_id == user_public_id))
        if row is None:
            now = datetime.now(timezone.utc)
            row = EntitlementRecord(
                user_public_id=user_public_id,
                plan="free",
                status="active",
                starts_at=now,
                ends_at=None,
                source="private-beta",
            )
            db.add(row)
            db.commit()
        return Entitlement(
            plan=row.plan,
            status=row.status,
            starts_at=_utc(row.starts_at),
            ends_at=_utc(row.ends_at) if row.ends_at else None,
            features=list(PLAN_FEATURES.get(row.plan, PLAN_FEATURES["free"])),
        )

    def create_alert(
        self,
        db: Session,
        *,
        user_public_id: str,
        symbol: str,
        condition: str,
        threshold: float,
    ) -> AlertRule:
        symbol = symbol.strip().upper()
        condition = condition.strip().lower()
        if symbol not in SUPPORTED_SYMBOLS:
            raise ProductError("Unsupported symbol")
        if condition not in {"above", "below"}:
            raise ProductError("condition must be above or below")
        if threshold <= 0:
            raise ProductError("threshold must be positive")
        row = AlertRuleRecord(
            alert_id=str(uuid4()),
            user_public_id=user_public_id,
            symbol=symbol,
            condition=condition,
            threshold=threshold,
            enabled=True,
            last_triggered_at=None,
            created_at=datetime.now(timezone.utc),
        )
        db.add(row)
        self.audit.record(
            db,
            action="alert.create",
            user_public_id=user_public_id,
            resource=row.alert_id,
            metadata={"symbol": symbol, "condition": condition},
            commit=False,
        )
        db.commit()
        return self._alert(row)

    def alerts(self, db: Session, user_public_id: str) -> list[AlertRule]:
        rows = list(
            db.scalars(
                select(AlertRuleRecord)
                .where(AlertRuleRecord.user_public_id == user_public_id)
                .order_by(AlertRuleRecord.created_at.desc())
            )
        )
        return [self._alert(row) for row in rows]

    def delete_alert(self, db: Session, *, user_public_id: str, alert_id: str) -> bool:
        row = db.scalar(
            select(AlertRuleRecord).where(
                AlertRuleRecord.alert_id == alert_id,
                AlertRuleRecord.user_public_id == user_public_id,
            )
        )
        if row is None:
            return False
        db.delete(row)
        self.audit.record(
            db,
            action="alert.delete",
            user_public_id=user_public_id,
            resource=alert_id,
            commit=False,
        )
        db.commit()
        return True

    def evaluate_alerts(
        self,
        db: Session,
        *,
        user_public_id: str,
        prices: dict[str, float],
    ) -> list[AlertRule]:
        rows = list(
            db.scalars(
                select(AlertRuleRecord).where(
                    AlertRuleRecord.user_public_id == user_public_id,
                    AlertRuleRecord.enabled.is_(True),
                )
            )
        )
        triggered: list[AlertRule] = []
        now = datetime.now(timezone.utc)
        for row in rows:
            price = prices.get(row.symbol)
            if price is None:
                continue
            hit = price > row.threshold if row.condition == "above" else price < row.threshold
            if hit:
                row.last_triggered_at = now
                triggered.append(self._alert(row))
        if triggered:
            db.commit()
        return triggered

    def watchlist(self, db: Session, user_public_id: str) -> WatchlistResponse:
        rows = list(db.scalars(
            select(WatchlistRecord)
            .where(WatchlistRecord.user_public_id == user_public_id)
            .order_by(WatchlistRecord.created_at.asc())
        ))
        return WatchlistResponse(items=[WatchlistItem(symbol=row.symbol, created_at=_utc(row.created_at)) for row in rows])

    def add_watchlist(self, db: Session, *, user_public_id: str, symbol: str) -> WatchlistItem:
        normalized = symbol.strip().upper()
        if normalized not in SUPPORTED_SYMBOLS:
            raise ProductError("Unsupported symbol")
        row = db.scalar(select(WatchlistRecord).where(
            WatchlistRecord.user_public_id == user_public_id,
            WatchlistRecord.symbol == normalized,
        ))
        if row is not None:
            return WatchlistItem(symbol=row.symbol, created_at=_utc(row.created_at))
        row = WatchlistRecord(
            user_public_id=user_public_id,
            symbol=normalized,
            created_at=datetime.now(timezone.utc),
        )
        db.add(row)
        self.audit.record(db, action="watchlist.add", user_public_id=user_public_id, resource=normalized, commit=False)
        db.commit()
        return WatchlistItem(symbol=normalized, created_at=_utc(row.created_at))

    def remove_watchlist(self, db: Session, *, user_public_id: str, symbol: str) -> bool:
        normalized = symbol.strip().upper()
        row = db.scalar(select(WatchlistRecord).where(
            WatchlistRecord.user_public_id == user_public_id,
            WatchlistRecord.symbol == normalized,
        ))
        if row is None:
            return False
        db.delete(row)
        self.audit.record(db, action="watchlist.remove", user_public_id=user_public_id, resource=normalized, commit=False)
        db.commit()
        return True

    def preferences(self, db: Session, user_public_id: str) -> PreferencesResponse:
        row = db.scalar(select(UserPreferenceRecord).where(UserPreferenceRecord.user_public_id == user_public_id))
        if row is None:
            now = datetime.now(timezone.utc)
            row = UserPreferenceRecord(user_public_id=user_public_id, preferences={}, updated_at=now)
            db.add(row)
            db.commit()
        return PreferencesResponse(preferences=dict(row.preferences or {}), updated_at=_utc(row.updated_at))

    def update_preferences(self, db: Session, *, user_public_id: str, values: dict[str, object]) -> PreferencesResponse:
        row = db.scalar(select(UserPreferenceRecord).where(UserPreferenceRecord.user_public_id == user_public_id))
        now = datetime.now(timezone.utc)
        if row is None:
            row = UserPreferenceRecord(user_public_id=user_public_id, preferences=dict(values), updated_at=now)
            db.add(row)
        else:
            row.preferences = dict(values)
            row.updated_at = now
        db.commit()
        return PreferencesResponse(preferences=dict(row.preferences), updated_at=_utc(row.updated_at))

    @staticmethod
    def _alert(row: AlertRuleRecord) -> AlertRule:
        return AlertRule(
            alert_id=row.alert_id,
            symbol=row.symbol,
            condition=row.condition,
            threshold=row.threshold,
            enabled=row.enabled,
            last_triggered_at=_utc(row.last_triggered_at) if row.last_triggered_at else None,
            created_at=_utc(row.created_at),
        )


def _utc(value: datetime) -> datetime:
    if value.tzinfo is None:
        return value.replace(tzinfo=timezone.utc)
    return value.astimezone(timezone.utc)
