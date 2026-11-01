from __future__ import annotations

from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta, timezone
from pathlib import Path
from threading import Event

from alembic import command
from alembic.config import Config
from fastapi.testclient import TestClient
import pytest
from pydantic import ValidationError
from sqlalchemy import create_engine, select, text
from sqlalchemy.orm import Session
from sqlalchemy.pool import StaticPool

from app.api.routes.auth import get_auth_email_sender
from app.core.config import Settings, get_settings
from app.db.base import Base
from app.db.session import get_db
from app.main import create_app
from app.models.auth import AccountTokenRecord, SessionRecord, UserRecord
from app.models.product import AuditLogRecord
from app.services.auth import AuthError, AuthService
from auth_helpers import CapturingEmailSender

EMAIL = "phase3@example.com"
PASSWORD = "SyntheticPass123"
PAYLOAD = {"email": EMAIL, "password": PASSWORD, "display_name": "Phase 3"}


@pytest.fixture
def suite():
    engine = create_engine("sqlite://", connect_args={"check_same_thread": False}, poolclass=StaticPool)
    Base.metadata.create_all(engine)
    db = Session(engine, expire_on_commit=False)
    sender = CapturingEmailSender()
    settings = Settings(environment="test", auto_create_tables=False, private_api_key="", jwt_secret="phase3-synthetic-auth-secret-long-enough")
    auth = AuthService(settings, email_sender=sender)
    # Each test gets its own middleware counters, as well as its own database.
    # Retain the actual abuse guard without leaking request quotas into peers.
    test_app = create_app()
    test_app.dependency_overrides[get_db] = lambda: db
    test_app.dependency_overrides[get_settings] = lambda: settings
    test_app.dependency_overrides[get_auth_email_sender] = lambda: sender
    try:
        with TestClient(test_app) as client:
            yield db, sender, auth, client
    finally:
        test_app.dependency_overrides.clear()
        db.close()
        engine.dispose()


def _verified(client, sender):
    assert client.post("/api/v1/auth/register", json=PAYLOAD).status_code == 201
    code = sender.code_for(EMAIL, "email_verification")
    response = client.post("/api/v1/auth/email-verification/confirm", json={"email": EMAIL, "code": code, "new_password": PASSWORD})
    assert response.status_code == 200
    return response.json()


def _age_sent(db, purpose):
    record = db.scalar(select(AccountTokenRecord).where(AccountTokenRecord.purpose == purpose).order_by(AccountTokenRecord.id.desc()))
    record.sent_at = datetime.now(timezone.utc) - timedelta(seconds=61)
    db.commit()


def test_register_blocks_activation_and_never_exposes_code(suite, caplog):
    db, sender, _, client = suite
    response = client.post("/api/v1/auth/register", json={**PAYLOAD, "email": " PHASE3@EXAMPLE.COM "})
    assert response.status_code == 201
    assert response.json() == {"email": EMAIL, "verification_required": True, "expires_in": 900, "resend_after": 60}
    user = db.scalar(select(UserRecord))
    assert user.is_active and not user.email_verified and user.email_verification_required
    assert user.password_hash.startswith("$argon2id$")
    assert db.scalar(select(SessionRecord)) is None
    code = sender.code_for(EMAIL, "email_verification")
    token = db.scalar(select(AccountTokenRecord))
    assert token.token_hash != code and len(token.token_hash) == 64
    assert 895 <= (token.expires_at.replace(tzinfo=timezone.utc) - token.created_at.replace(tzinfo=timezone.utc)).total_seconds() <= 905
    login = client.post("/api/v1/auth/login", json={"email": EMAIL, "password": PASSWORD})
    assert login.status_code == 403
    assert login.json()["error"]["code"] == "email_verification_required"
    assert code not in response.text and PASSWORD not in caplog.text and code not in caplog.text
    assert code not in " ".join(row.metadata_json for row in db.scalars(select(AuditLogRecord)))


def test_pending_duplicate_and_confirmed_duplicate_are_distinct(suite):
    _, sender, _, client = suite
    assert client.post("/api/v1/auth/register", json=PAYLOAD).status_code == 201
    duplicate = client.post("/api/v1/auth/register", json=PAYLOAD)
    assert duplicate.status_code == 409 and duplicate.json()["error"]["code"] == "account_pending_verification"
    code = sender.code_for(EMAIL, "email_verification")
    assert client.post("/api/v1/auth/email-verification/confirm", json={"email": EMAIL, "code": code, "new_password": PASSWORD}).status_code == 200
    duplicate = client.post("/api/v1/auth/register", json=PAYLOAD)
    assert duplicate.status_code == 422 and duplicate.json()["error"]["code"] == "account_exists"


def test_verified_account_login_refresh_and_single_use(suite):
    db, sender, _, client = suite
    tokens = _verified(client, sender)
    code = sender.code_for(EMAIL, "email_verification")
    headers = {"Authorization": f"Bearer {tokens['access_token']}"}
    assert client.get("/api/v1/auth/me", headers=headers).json()["email_verified"] is True
    assert db.scalar(select(UserRecord)).is_active
    assert client.post("/api/v1/auth/email-verification/confirm", json={"email": EMAIL, "code": code, "new_password": PASSWORD}).status_code == 422
    assert client.post("/api/v1/auth/login", json={"email": EMAIL, "password": PASSWORD}).status_code == 200
    rotation = client.post("/api/v1/auth/refresh", json={"refresh_token": tokens["refresh_token"]})
    assert rotation.status_code == 200
    assert rotation.json()["refresh_token"] != tokens["refresh_token"]
    assert client.post("/api/v1/auth/refresh", json={"refresh_token": tokens["refresh_token"]}).status_code == 401


@pytest.mark.parametrize("purpose,route", [
    ("email_verification", "email-verification"), ("password_reset", "password-reset"),
])
def test_resend_cooldown_replaces_old_code(suite, purpose, route):
    db, sender, _, client = suite
    if purpose == "password_reset":
        _verified(client, sender)
        assert client.post(f"/api/v1/auth/{route}/request", json={"email": EMAIL}).status_code == 200
    else:
        assert client.post("/api/v1/auth/register", json=PAYLOAD).status_code == 201
    old = sender.code_for(EMAIL, purpose)
    response = client.post(f"/api/v1/auth/{route}/request", json={"email": EMAIL})
    assert response.status_code == 429 and response.json()["error"]["code"] == "otp_resend_limited"
    assert 1 <= int(response.headers["Retry-After"]) <= 60
    _age_sent(db, purpose)
    assert client.post(f"/api/v1/auth/{route}/request", json={"email": EMAIL}).status_code == 200
    new = sender.code_for(EMAIL, purpose)
    assert new != old
    confirm = {"email": EMAIL, "code": old, "new_password": PASSWORD}
    if purpose == "password_reset":
        confirm["new_password"] = "ReplacementPass123"
    assert client.post(f"/api/v1/auth/{route}/confirm", json=confirm).json()["error"]["code"] == "otp_invalid"
    confirm["code"] = new
    assert client.post(f"/api/v1/auth/{route}/confirm", json=confirm).status_code == (204 if purpose == "password_reset" else 200)
    pending = list(db.scalars(select(AccountTokenRecord).where(AccountTokenRecord.purpose == purpose, AccountTokenRecord.used_at.is_(None))))
    assert not pending


@pytest.mark.parametrize("route,purpose", [("email-verification", "email_verification"), ("password-reset", "password_reset")])
def test_expired_code_has_explicit_resend_error(suite, route, purpose):
    db, sender, _, client = suite
    if purpose == "password_reset":
        _verified(client, sender)
        client.post(f"/api/v1/auth/{route}/request", json={"email": EMAIL})
    else:
        client.post("/api/v1/auth/register", json=PAYLOAD)
    record = db.scalar(select(AccountTokenRecord).where(AccountTokenRecord.purpose == purpose))
    record.expires_at = datetime.now(timezone.utc) - timedelta(seconds=1)
    db.commit()
    payload = {"email": EMAIL, "code": sender.code_for(EMAIL, purpose), "new_password": PASSWORD}
    if purpose == "password_reset":
        payload["new_password"] = "ReplacementPass123"
    response = client.post(f"/api/v1/auth/{route}/confirm", json=payload)
    assert response.status_code == 422 and response.json()["error"]["code"] == "otp_expired"
    _age_sent(db, purpose)
    assert client.post(f"/api/v1/auth/{route}/request", json={"email": EMAIL}).status_code == 200


def test_wrong_codes_are_bounded_and_do_not_activate(suite):
    db, sender, _, client = suite
    client.post("/api/v1/auth/register", json=PAYLOAD)
    right = sender.code_for(EMAIL, "email_verification")
    wrong = f"{(int(right) + 1) % 1_000_000:06d}"
    for attempt in range(5):
        response = client.post("/api/v1/auth/email-verification/confirm", json={"email": EMAIL, "code": wrong, "new_password": PASSWORD})
        assert response.json()["error"]["code"] == ("otp_attempts_exceeded" if attempt == 4 else "otp_invalid")
    assert client.post("/api/v1/auth/email-verification/confirm", json={"email": EMAIL, "code": right, "new_password": PASSWORD}).status_code == 429
    record = db.scalar(select(AccountTokenRecord))
    assert record.attempt_count == 5 and record.used_at is not None
    assert not db.scalar(select(UserRecord)).email_verified
    assert db.scalar(select(SessionRecord)) is None


@pytest.mark.parametrize("purpose,route", [
    ("email_verification", "email-verification"), ("password_reset", "password-reset"),
])
@pytest.mark.parametrize("invalid_state", ["wrong", "expired", "replaced"])
def test_rejected_challenge_preserves_account_and_keeps_secrets_private(suite, caplog, purpose, route, invalid_state):
    db, sender, _, client = suite
    responses = []
    if purpose == "password_reset":
        session = _verified(client, sender)
        responses.append(client.post(f"/api/v1/auth/{route}/request", json={"email": EMAIL}))
    else:
        session = None
        responses.append(client.post("/api/v1/auth/register", json=PAYLOAD))
    old_code = sender.code_for(EMAIL, purpose)
    challenge = db.scalar(select(AccountTokenRecord).where(
        AccountTokenRecord.purpose == purpose,
    ).order_by(AccountTokenRecord.id.desc()))
    if invalid_state == "expired":
        challenge.expires_at = datetime.now(timezone.utc) - timedelta(seconds=1)
        db.commit()
    elif invalid_state == "replaced":
        _age_sent(db, purpose)
        responses.append(client.post(f"/api/v1/auth/{route}/request", json={"email": EMAIL}))
        assert responses[-1].status_code == 200
        assert sender.code_for(EMAIL, purpose) != old_code
        db.refresh(challenge)
        assert challenge.used_at is not None
    submitted = f"{(int(old_code) + 1) % 1_000_000:06d}" if invalid_state == "wrong" else old_code
    user = db.scalar(select(UserRecord))
    original_hash = user.password_hash
    original_verification = user.email_verified
    original_session_count = len(list(db.scalars(select(SessionRecord))))
    replacement_password = "SyntheticRejectionGuard456"
    rejected = client.post(f"/api/v1/auth/{route}/confirm", json={
        "email": EMAIL, "code": submitted, "new_password": replacement_password,
    })
    responses.append(rejected)
    assert rejected.status_code == 422
    assert rejected.json()["error"]["code"] == ("otp_expired" if invalid_state == "expired" else "otp_invalid")
    db.refresh(user)
    assert user.password_hash == original_hash
    assert user.email_verified == original_verification
    assert len(list(db.scalars(select(SessionRecord)))) == original_session_count
    if session:
        me = client.get("/api/v1/auth/me", headers={"Authorization": f"Bearer {session['access_token']}"})
        responses.append(me)
        assert me.status_code == 200
    # After a failed confirmation the rightful owner can still recover.
    if invalid_state == "expired":
        _age_sent(db, purpose)
        responses.append(client.post(f"/api/v1/auth/{route}/request", json={"email": EMAIL}))
        assert responses[-1].status_code == 200
    valid_code = sender.code_for(EMAIL, purpose)
    accepted = client.post(f"/api/v1/auth/{route}/confirm", json={
        "email": EMAIL, "code": valid_code, "new_password": replacement_password,
    })
    responses.append(accepted)
    assert accepted.status_code == (204 if purpose == "password_reset" else 200)
    for secret in {PASSWORD, replacement_password, submitted, old_code, valid_code}:
        assert secret not in caplog.text
        assert all(secret not in response.text for response in responses)
        assert all(secret not in row.metadata_json for row in db.scalars(select(AuditLogRecord)))
    assert user.password_hash.startswith("$argon2id$")
    for record in db.scalars(select(AccountTokenRecord)):
        assert record.token_hash not in {old_code, valid_code, submitted}
        assert len(record.token_hash) == 64


def test_failed_signup_delivery_remains_pending_and_can_retry(suite):
    db, sender, _, client = suite
    sender.fail = True
    response = client.post("/api/v1/auth/register", json=PAYLOAD)
    assert response.status_code == 503 and response.json()["error"]["code"] == "email_delivery_failed"
    assert "Synthetic delivery" not in response.text
    assert db.scalar(select(UserRecord)) is not None
    assert db.scalar(select(AccountTokenRecord)) is None
    assert db.scalar(select(SessionRecord)) is None
    sender.fail = False
    assert client.post("/api/v1/auth/email-verification/request", json={"email": EMAIL}).status_code == 200
    code = sender.code_for(EMAIL, "email_verification")
    assert client.post("/api/v1/auth/email-verification/confirm", json={"email": EMAIL, "code": code, "new_password": PASSWORD}).status_code == 200


def test_failed_recovery_resend_preserves_previous_valid_code(suite):
    db, sender, _, client = suite
    _verified(client, sender)
    client.post("/api/v1/auth/password-reset/request", json={"email": EMAIL})
    code = sender.code_for(EMAIL, "password_reset")
    _age_sent(db, "password_reset")
    sender.fail = True
    response = client.post("/api/v1/auth/password-reset/request", json={"email": EMAIL})
    assert response.status_code == 503
    sender.fail = False
    assert client.post("/api/v1/auth/password-reset/confirm", json={"email": EMAIL, "code": code, "new_password": "ReplacementPass123"}).status_code == 204


def test_reset_revokes_all_personal_and_shared_route_tokens(suite):
    db, sender, _, client = suite
    first = _verified(client, sender)
    second = client.post("/api/v1/auth/login", json={"email": EMAIL, "password": PASSWORD}).json()
    assert client.post("/api/v1/auth/password-reset/request", json={"email": EMAIL}).status_code == 200
    code = sender.code_for(EMAIL, "password_reset")
    assert client.post("/api/v1/auth/password-reset/confirm", json={"email": EMAIL, "code": code, "new_password": "ReplacementPass123"}).status_code == 204
    for tokens in (first, second):
        headers = {"Authorization": f"Bearer {tokens['access_token']}"}
        for route in ("/api/v1/auth/me", "/api/v1/watchlist", "/api/v1/market/assets", "/api/v1/history/candles?symbol=BTC"):
            assert client.get(route, headers=headers).status_code == 401
        assert client.post("/api/v1/auth/refresh", json={"refresh_token": tokens["refresh_token"]}).status_code == 401
    assert all(row.revoked_at is not None for row in db.scalars(select(SessionRecord)))
    assert client.post("/api/v1/auth/login", json={"email": EMAIL, "password": PASSWORD}).status_code == 401
    assert client.post("/api/v1/auth/login", json={"email": EMAIL, "password": "ReplacementPass123"}).status_code == 200
    assert client.post("/api/v1/auth/password-reset/confirm", json={"email": EMAIL, "code": code, "new_password": "ThirdPassword123"}).status_code == 422


def test_unknown_reset_response_has_no_debug_token_or_claimed_delivery(suite):
    _, sender, _, client = suite
    response = client.post("/api/v1/auth/password-reset/request", json={"email": "unknown@example.com"})
    assert response.status_code == 200
    assert response.json() == {"accepted": True, "expires_in": 900, "resend_after": 60}
    assert not sender.messages


def test_persian_digits_and_leading_zero_code(suite, monkeypatch):
    _, sender, _, client = suite
    monkeypatch.setattr("app.services.auth.secrets.randbelow", lambda limit: 42)
    client.post("/api/v1/auth/register", json=PAYLOAD)
    assert sender.code_for(EMAIL, "email_verification") == "000042"
    assert client.post("/api/v1/auth/email-verification/confirm", json={"email": EMAIL, "code": "۰۰۰۰۴۲", "new_password": PASSWORD}).status_code == 200


def test_legacy_active_user_not_falsely_verified_or_blocked(suite):
    db, _, auth, client = suite
    now = datetime.now(timezone.utc)
    user = UserRecord(public_id="legacy-active", email=EMAIL, display_name="Legacy", password_hash=auth.hasher.hash(PASSWORD), is_active=True, email_verified=False, email_verification_required=False, created_at=now, updated_at=now)
    db.add(user)
    db.commit()
    response = client.post("/api/v1/auth/login", json={"email": EMAIL, "password": PASSWORD})
    assert response.status_code == 200 and response.json()["user"]["email_verified"] is False


@pytest.mark.parametrize("verified", [False, True])
def test_suspended_legacy_accounts_stay_suspended(suite, verified):
    db, _, auth, client = suite
    now = datetime.now(timezone.utc)
    db.add(UserRecord(public_id="legacy-suspended", email=EMAIL, display_name="Legacy", password_hash=auth.hasher.hash(PASSWORD), is_active=False, email_verified=verified, email_verification_required=False, created_at=now, updated_at=now))
    db.commit()
    assert client.post("/api/v1/auth/login", json={"email": EMAIL, "password": PASSWORD}).status_code == 403
    response = client.post("/api/v1/auth/password-reset/request", json={"email": EMAIL})
    assert response.status_code == 403
    assert not db.scalar(select(UserRecord)).is_active


def test_suspended_pending_signup_cannot_verify_or_reset(suite):
    db, sender, _, client = suite
    assert client.post("/api/v1/auth/register", json=PAYLOAD).status_code == 201
    user = db.scalar(select(UserRecord))
    user.is_active = False
    db.commit()
    code = sender.code_for(EMAIL, "email_verification")
    for route, payload in (
        ("email-verification/request", {"email": EMAIL}),
        ("email-verification/confirm", {"email": EMAIL, "code": code, "new_password": PASSWORD}),
        ("password-reset/request", {"email": EMAIL}),
    ):
        response = client.post(f"/api/v1/auth/{route}", json=payload)
        assert response.status_code == 403 and response.json()["error"]["code"] == "account_unavailable"
    assert not user.is_active and not user.email_verified
    assert db.scalar(select(SessionRecord)) is None


@pytest.mark.parametrize("route,payload,secret", [
    ("register", {**PAYLOAD, "password": ["raw-password-hidden"]}, "raw-password-hidden"),
    ("email-verification/confirm", {"email": EMAIL, "code": ["000042"], "new_password": PASSWORD}, "000042"),
    ("password-reset/confirm", {"email": EMAIL, "code": "000042", "new_password": ["new-password-hidden"]}, "new-password-hidden"),
    ("refresh", {"refresh_token": ["refresh-hidden"]}, "refresh-hidden"),
])
def test_validation_never_echoes_secret_inputs(suite, route, payload, secret):
    _, _, _, client = suite
    response = client.post(f"/api/v1/auth/{route}", json=payload)
    assert response.status_code == 422
    assert secret not in response.text
    assert all("input" not in item and "ctx" not in item for item in response.json()["detail"])


def test_concurrent_confirmation_creates_only_one_session(suite):
    db, sender, auth, _ = suite
    auth.register(db, **PAYLOAD, device_name="Test")
    code = sender.code_for(EMAIL, "email_verification")
    engine = db.get_bind()

    def confirm():
        with Session(engine, expire_on_commit=False) as thread_db:
            try:
                auth.confirm_email_verification(thread_db, email=EMAIL, code=code, new_password=PASSWORD, device_name="Test")
                return "verified"
            except AuthError as exc:
                return exc.code

    with ThreadPoolExecutor(max_workers=2) as pool:
        result = list(pool.map(lambda _: confirm(), range(2)))
    assert sorted(result) == ["otp_invalid", "verified"]
    assert len(list(db.scalars(select(SessionRecord)))) == 1


def test_mailbox_owner_replaces_preregistered_password(suite):
    _, sender, _, client = suite
    assert client.post("/api/v1/auth/register", json=PAYLOAD).status_code == 201
    owner_password = "OwnerChosenPass456"
    owner_attempt = client.post("/api/v1/auth/register", json={**PAYLOAD, "password": owner_password})
    assert owner_attempt.status_code == 409
    code = sender.code_for(EMAIL, "email_verification")
    confirmation = client.post("/api/v1/auth/email-verification/confirm", json={
        "email": EMAIL, "code": code, "new_password": owner_password,
    })
    assert confirmation.status_code == 200
    assert client.post("/api/v1/auth/login", json={"email": EMAIL, "password": PASSWORD}).status_code == 401
    assert client.post("/api/v1/auth/login", json={"email": EMAIL, "password": owner_password}).status_code == 200


@pytest.mark.parametrize("operation", ["login", "refresh"])
def test_reset_serializes_inflight_login_and_refresh(suite, monkeypatch, operation):
    db, sender, auth, client = suite
    original = _verified(client, sender)
    auth.create_password_reset(db, EMAIL)
    code = sender.code_for(EMAIL, "password_reset")
    authenticated = Event()
    reset_started = Event()
    encode = auth._access_token

    def pause_before_commit(user_id, session_id, now):
        authenticated.set()
        assert reset_started.wait(5)
        return encode(user_id, session_id, now)

    monkeypatch.setattr(auth, "_access_token", pause_before_commit)
    engine = db.get_bind()

    def authenticate():
        with Session(engine, expire_on_commit=False) as thread_db:
            if operation == "login":
                return auth.login(thread_db, email=EMAIL, password=PASSWORD, device_name="Concurrent")
            return auth.refresh(thread_db, original["refresh_token"])

    def reset():
        assert authenticated.wait(5)
        reset_started.set()
        with Session(engine, expire_on_commit=False) as thread_db:
            auth.confirm_password_reset(thread_db, email=EMAIL, code=code, new_password="ReplacementPass123")

    with ThreadPoolExecutor(max_workers=2) as pool:
        login_future = pool.submit(authenticate)
        reset_future = pool.submit(reset)
        tokens = login_future.result(timeout=15)
        reset_future.result(timeout=15)
    with Session(engine) as check_db:
        with pytest.raises(AuthError):
            auth.resolve_identity(check_db, tokens.access_token)
        with pytest.raises(AuthError):
            auth.refresh(check_db, tokens.refresh_token)
        assert all(row.revoked_at is not None for row in check_db.scalars(select(SessionRecord)))


def test_login_waiting_for_reset_rechecks_new_password(suite, monkeypatch):
    db, sender, auth, client = suite
    _verified(client, sender)
    auth.create_password_reset(db, EMAIL)
    code = sender.code_for(EMAIL, "password_reset")
    reset_locked = Event()
    login_started = Event()
    consume = auth._consume_challenge

    def pause_after_consume(thread_db, user, purpose, entered):
        consume(thread_db, user, purpose, entered)
        reset_locked.set()
        assert login_started.wait(5)

    monkeypatch.setattr(auth, "_consume_challenge", pause_after_consume)
    engine = db.get_bind()

    def reset():
        with Session(engine, expire_on_commit=False) as thread_db:
            auth.confirm_password_reset(thread_db, email=EMAIL, code=code, new_password="ReplacementPass123")

    def login():
        assert reset_locked.wait(5)
        login_started.set()
        with Session(engine, expire_on_commit=False) as thread_db:
            with pytest.raises(AuthError) as failure:
                auth.login(thread_db, email=EMAIL, password=PASSWORD, device_name="Concurrent")
            return failure.value.code

    with ThreadPoolExecutor(max_workers=2) as pool:
        reset_future = pool.submit(reset)
        login_future = pool.submit(login)
        reset_future.result(timeout=15)
        assert login_future.result(timeout=15) == "invalid_credentials"


@pytest.mark.parametrize("purpose", ["email_verification", "password_reset"])
def test_confirmation_transaction_rolls_back_on_database_work_failure(suite, monkeypatch, purpose):
    db, sender, auth, client = suite
    if purpose == "password_reset":
        _verified(client, sender)
        auth.create_password_reset(db, EMAIL)
    else:
        auth.register(db, **PAYLOAD, device_name="Test")
    code = sender.code_for(EMAIL, purpose)
    original_hash = db.scalar(select(UserRecord)).password_hash

    def fail_audit(*args, **kwargs):
        raise RuntimeError("Synthetic database failure")

    monkeypatch.setattr(auth.audit, "record", fail_audit)
    with pytest.raises(RuntimeError):
        if purpose == "password_reset":
            auth.confirm_password_reset(db, email=EMAIL, code=code, new_password="ReplacementPass123")
        else:
            auth.confirm_email_verification(db, email=EMAIL, code=code, new_password="ReplacementPass123", device_name="Test")
    db.rollback()
    assert db.scalar(select(UserRecord)).password_hash == original_hash
    challenge = db.scalar(select(AccountTokenRecord).where(AccountTokenRecord.purpose == purpose))
    assert challenge.used_at is None
    if purpose == "password_reset":
        assert all(row.revoked_at is None for row in db.scalars(select(SessionRecord)))
    else:
        assert not db.scalar(select(UserRecord)).email_verified
        assert db.scalar(select(SessionRecord)) is None


def test_migration_preserves_legacy_users_and_invalidates_duplicate_tokens(tmp_path, monkeypatch):
    database = tmp_path / "phase3-migration.db"
    monkeypatch.setenv("GOLDBRAIN_DATABASE_URL", f"sqlite:///{database.as_posix()}")
    get_settings.cache_clear()
    config = Config(str(Path(__file__).resolve().parents[1] / "alembic.ini"))
    config.set_main_option("script_location", str(Path(__file__).resolve().parents[1] / "migrations"))
    try:
        command.upgrade(config, "0009_phase5_backend_core")
        engine = create_engine(f"sqlite:///{database.as_posix()}")
        now = datetime.now(timezone.utc)
        with engine.begin() as connection:
            for name, active in (("legacy-active", True), ("legacy-suspended", False)):
                connection.execute(text("INSERT INTO users(public_id,email,display_name,password_hash,role,is_active,email_verified,mfa_enabled,created_at,updated_at) VALUES(:id,:email,:name,'synthetic-hash','user',:active,0,0,:now,:now)"), {"id": name, "email": f"{name}@example.com", "name": name, "active": active, "now": now})
            for index in range(3):
                connection.execute(text("INSERT INTO account_tokens(token_hash,user_public_id,purpose,created_at,expires_at,used_at) VALUES(:hash,'legacy-active','password_reset',:now,:expiry,NULL)"), {"hash": f"synthetic-token-{index}", "now": now, "expiry": now + timedelta(minutes=30)})
        command.upgrade(config, "head")
        with engine.connect() as connection:
            rows = connection.execute(text("SELECT public_id,is_active,email_verified,email_verification_required FROM users ORDER BY public_id")).all()
            assert rows == [("legacy-active", 1, 0, 0), ("legacy-suspended", 0, 0, 0)]
            assert connection.scalar(text("SELECT count(*) FROM account_tokens WHERE used_at IS NULL")) == 0
            assert connection.scalar(text("SELECT count(*) FROM account_tokens")) == 3
        engine.dispose()
    finally:
        get_settings.cache_clear()


def test_settings_validation_exception_never_echoes_secret_values():
    markers = {"smtp_password": "synthetic-smtp-secret-marker", "jwt_secret": "synthetic-jwt-secret-marker", "NAVASAN_API_KEY": "synthetic-provider-secret-marker"}
    with pytest.raises(ValidationError) as failure:
        Settings(_env_file=None, environment="production", private_api_key="", auto_create_tables=False, **markers)
    for marker in markers.values():
        assert marker not in str(failure.value)
