from sqlalchemy import create_engine
from sqlalchemy.orm import Session
from sqlalchemy.pool import StaticPool

from app.core.config import Settings
from app.db.base import Base
from app.services.auth import AuthService
from app.services.product import ProductService
from auth_helpers import CapturingEmailSender, register_verified


def _session() -> Session:
    engine = create_engine(
        "sqlite://",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    Base.metadata.create_all(engine)
    return Session(engine)


def _settings() -> Settings:
    return Settings(
        environment="test",
        auto_create_tables=False,
        jwt_secret="test-secret-that-is-long-enough-for-unit-tests",
        private_api_key="",
    )


def test_register_login_refresh_and_session_revocation() -> None:
    db = _session()
    sender = CapturingEmailSender()
    auth = AuthService(_settings(), email_sender=sender)
    registered = register_verified(
        auth, db, sender,
        email="ali@example.com",
        password="StrongPass123",
        display_name="Ali",
        device_name="Desktop",
    )
    assert registered.user.email == "ali@example.com"
    assert registered.access_token
    assert registered.refresh_token

    identity = auth.resolve_identity(db, registered.access_token)
    assert identity.user.public_id == registered.user.public_id

    refreshed = auth.refresh(db, registered.refresh_token)
    assert refreshed.refresh_token != registered.refresh_token
    assert refreshed.session_id == registered.session_id

    logged_in = auth.login(
        db,
        email="ali@example.com",
        password="StrongPass123",
        device_name="Second device",
    )
    sessions = auth.list_sessions(
        db,
        user_public_id=registered.user.public_id,
        current_session_id=logged_in.session_id,
    )
    assert len(sessions) == 2
    assert auth.revoke_session(
        db,
        user_public_id=registered.user.public_id,
        session_id=registered.session_id,
    )


def test_entitlement_and_alert_lifecycle() -> None:
    db = _session()
    sender = CapturingEmailSender()
    auth = AuthService(_settings(), email_sender=sender)
    registered = register_verified(
        auth, db, sender,
        email="friend@example.com",
        password="AnotherPass123",
        display_name="Friend",
        device_name="Laptop",
    )
    product = ProductService()
    entitlement = product.entitlement(db, registered.user.public_id)
    assert entitlement.plan == "free"
    alert = product.create_alert(
        db,
        user_public_id=registered.user.public_id,
        symbol="BTC",
        condition="above",
        threshold=100_000,
    )
    assert alert.symbol == "BTC"
    assert product.alerts(db, registered.user.public_id)[0].alert_id == alert.alert_id
    assert product.delete_alert(
        db,
        user_public_id=registered.user.public_id,
        alert_id=alert.alert_id,
    )
