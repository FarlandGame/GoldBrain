from __future__ import annotations

from datetime import datetime, timedelta, timezone
from fastapi.testclient import TestClient
from sqlalchemy import Engine, create_engine
from sqlalchemy.orm import Session
from sqlalchemy.pool import StaticPool

from app.core.config import Settings, get_settings
from app.db.base import Base
from app.db.session import get_db
from app.main import app
from app.models.candle import MarketCandleRecord
from app.api.dependencies import get_market_service
from app.services.market_data import QuoteBatch
from app.api.routes.auth import get_auth_email_sender
from auth_helpers import CapturingEmailSender


class _FakeMarketService:
    async def fetch_quotes(self, symbols, force_refresh: bool = False):
        del force_refresh
        now = datetime.now(timezone.utc)
        quotes = {
            symbol: {
                "symbol": symbol,
                "name": symbol,
                "currency": "USDT" if symbol == "BTC" else "IRT",
                "price": 65_000.0 if symbol == "BTC" else 230_000.0,
                "updated_at": now,
                "provider": "test-provider",
                "unit": "coin",
                "market": "GLOBAL" if symbol == "BTC" else "IRAN",
                "provider_timestamp": now,
                "received_at": now,
                "freshness_status": "LIVE",
                "data_quality_status": "VALID",
            }
            for symbol in symbols
        }
        from app.schemas.market import MarketQuote

        return QuoteBatch(
            requested=tuple(symbols),
            quotes={key: MarketQuote.model_validate(value) for key, value in quotes.items()},
            issues={},
        )

    def drain_observability(self):
        return []


def _db() -> tuple[Session, Engine]:
    engine = create_engine("sqlite://", connect_args={"check_same_thread": False}, poolclass=StaticPool)
    Base.metadata.create_all(engine)
    return Session(engine), engine


def _overrides(db: Session) -> CapturingEmailSender:
    app.dependency_overrides[get_db] = lambda: db
    app.dependency_overrides[get_settings] = lambda: Settings(
        environment="test",
        auto_create_tables=False,
        private_api_key="",
        jwt_secret="phase5-test-secret-that-is-long-enough",
    )
    app.dependency_overrides[get_market_service] = lambda: _FakeMarketService()
    sender = CapturingEmailSender()
    app.dependency_overrides[get_auth_email_sender] = lambda: sender
    return sender


def _register_verified(client: TestClient, sender: CapturingEmailSender, body: dict[str, str]):
    response = client.post("/api/v1/auth/register", json=body)
    assert response.status_code == 201
    verified = client.post("/api/v1/auth/email-verification/confirm", json={
        "email": body["email"], "code": sender.code_for(body["email"], "email_verification"), "new_password": body["password"],
    })
    assert verified.status_code == 200
    return verified


def _seed_history(db: Session, count: int = 40) -> None:
    now = datetime.now(timezone.utc).replace(minute=0, second=0, microsecond=0)
    for index in range(count, 0, -1):
        opened = now - timedelta(hours=index)
        close = 65_000.0 + (count - index) * 25.0
        db.add(MarketCandleRecord(
            symbol="BTC", timeframe="1h", currency="USDT", provider="test-provider",
            opened_at=opened, closed_at=opened + timedelta(hours=1),
            open=close - 10.0, high=close + 20.0, low=close - 20.0, close=close,
            volume=1.0, unit="coin", market="GLOBAL", provider_timestamp=opened,
            received_at=opened + timedelta(seconds=1), latency_ms=10,
            freshness_status="FRESH", data_quality_status="VALID", quality_flags=[],
            source_tick_ids=[], is_complete=True,
        ))
    db.commit()


def test_auth_watchlist_and_logout_all_flow() -> None:
    db, engine = _db()
    sender = _overrides(db)
    try:
        with TestClient(app) as client:
            payload = {"email": "phase5@example.com", "password": "StrongPass123", "display_name": "Phase 5"}
            _register_verified(client, sender, payload)
            tokens = client.post(
                "/api/v1/auth/login", json={"email": payload["email"], "password": payload["password"], "device_name": "Audit"}
            ).json()
            headers = {"Authorization": f"Bearer {tokens['access_token']}"}
            assert client.get("/api/v1/auth/me", headers=headers).status_code == 200
            assert client.get("/api/v1/market/BTC/quote", headers=headers).status_code == 200
            _seed_history(db)
            assert client.get("/api/v1/market/BTC/candles?timeframe=1h&limit=5", headers=headers).status_code == 200
            assert client.post(
                "/api/v1/forecasts", json={"symbol": "BTC", "horizon": "1h", "timeframe": "1h"}, headers=headers
            ).status_code == 200
            assert client.post("/api/v1/watchlist", json={"symbol": "BTC"}, headers=headers).status_code == 201
            assert client.get("/api/v1/watchlist", headers=headers).json()["items"][0]["symbol"] == "BTC"
            assert client.post("/api/v1/auth/logout-all", headers=headers).status_code == 204
            assert client.get("/api/v1/auth/me", headers=headers).status_code == 401
    finally:
        app.dependency_overrides.clear()
        db.close()
        engine.dispose()


def test_refresh_rotation_and_revocation() -> None:
    db, engine = _db()
    sender = _overrides(db)
    try:
        with TestClient(app) as client:
            body = {"email": "rotate@example.com", "password": "StrongPass123", "display_name": "Rotate"}
            original = _register_verified(client, sender, body).json()
            refreshed = client.post("/api/v1/auth/refresh", json={"refresh_token": original["refresh_token"]})
            assert refreshed.status_code == 200
            assert refreshed.json()["refresh_token"] != original["refresh_token"]
            assert client.post("/api/v1/auth/refresh", json={"refresh_token": original["refresh_token"]}).status_code == 401
            assert client.post("/api/v1/auth/logout", json={"refresh_token": refreshed.json()["refresh_token"]}).status_code == 204
    finally:
        app.dependency_overrides.clear()
        db.close()
        engine.dispose()


def test_duplicate_registration_and_invalid_protected_route() -> None:
    db, engine = _db()
    sender = _overrides(db)
    try:
        with TestClient(app) as client:
            payload = {"email": "duplicate@example.com", "password": "StrongPass123", "display_name": "Duplicate"}
            _register_verified(client, sender, payload)
            duplicate = client.post("/api/v1/auth/register", json=payload)
            assert duplicate.status_code == 422
            assert duplicate.json()["error"]["code"] == "account_exists"
            assert client.get("/api/v1/watchlist").status_code == 401
    finally:
        app.dependency_overrides.clear()
        db.close()
        engine.dispose()
