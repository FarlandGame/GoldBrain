from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
import hashlib
import hmac
import math
import re
import secrets
import threading
import time
import unicodedata
from uuid import uuid4

from argon2 import PasswordHasher
from argon2.exceptions import InvalidHashError, VerifyMismatchError
import jwt
from sqlalchemy import select, update
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.core.config import Settings
from app.models.auth import AccountTokenRecord, SessionRecord, UserRecord
from app.models.product import EntitlementRecord
from app.schemas.auth import AuthTokens, RegistrationPending, SessionInfo, UserProfile
from app.services.audit import AuditService
from app.services.auth_email import AuthEmailPurpose, AuthEmailSender, EmailDeliveryError


EMAIL_RE = re.compile(r"^[^\s@]+@[^\s@]+\.[^\s@]+$")


class AuthError(ValueError):
    def __init__(
        self, message: str, *, code: str = "auth_error", status_code: int | None = None,
        retry_after: int | None = None,
    ) -> None:
        super().__init__(message)
        self.code = code
        self.status_code = status_code
        self.retry_after = retry_after


@dataclass(frozen=True)
class Identity:
    user: UserRecord
    session: SessionRecord


class AuthService:
    _failed_logins: dict[str, list[float]] = {}
    _failed_logins_lock = threading.Lock()
    _max_failed_logins = 5
    _failed_window_seconds = 600.0
    # SQLite development uses one process. PostgreSQL additionally locks the
    # user row, and the partial unique index protects multi-worker issuance.
    _challenge_lock = threading.RLock()
    _challenge_minutes = 15
    _resend_seconds = 60
    _max_code_attempts = 5

    def __init__(self, settings: Settings, *, email_sender: AuthEmailSender | None = None) -> None:
        self.settings = settings
        self.hasher = PasswordHasher(time_cost=3, memory_cost=65536, parallelism=2, hash_len=32, salt_len=16)
        self.audit = AuditService()
        self.email_sender = email_sender if email_sender is not None else AuthEmailSender(settings)

    def register(
        self,
        db: Session,
        *,
        email: str,
        password: str,
        display_name: str,
        device_name: str,
        fingerprint: str | None = None,
    ) -> RegistrationPending:
        # A pending registration does not create a session. Device information
        # is submitted again on successful code confirmation.
        del device_name, fingerprint
        normalized_email = self._email(email)
        self._validate_password(password)
        name = display_name.strip()
        if not name or len(name) > 100:
            raise AuthError("display_name must be between 1 and 100 characters")
        existing = db.scalar(select(UserRecord).where(UserRecord.email == normalized_email))
        if existing is not None:
            if existing.email_verification_required and not existing.email_verified:
                raise AuthError(
                    "Verify your email to finish registration. You can request another code.",
                    code="account_pending_verification", status_code=409,
                )
            raise AuthError("An account with this email already exists", code="account_exists")
        now = datetime.now(timezone.utc)
        user = UserRecord(
            public_id=str(uuid4()),
            email=normalized_email,
            display_name=name,
            password_hash=self.hasher.hash(password),
            role="user",
            # is_active is the administrative suspension flag. Verification
            # separately gates all session creation/access for new accounts.
            is_active=True,
            email_verified=False,
            email_verification_required=True,
            mfa_enabled=False,
            created_at=now,
            updated_at=now,
        )
        db.add(user)
        db.add(
            EntitlementRecord(
                user_public_id=user.public_id,
                plan="free",
                status="active",
                starts_at=now,
                ends_at=None,
                source="private-beta",
            )
        )
        try:
            db.flush()
        except IntegrityError as exc:
            db.rollback()
            raise AuthError("An account with this email already exists", code="account_exists") from exc
        self.audit.record(db, action="auth.register", user_public_id=user.public_id, resource="user", commit=False)
        # Persist the pending account even if delivery fails, so resend works.
        db.commit()
        self.request_email_verification(db, normalized_email)
        return RegistrationPending(email=normalized_email)

    def login(
        self,
        db: Session,
        *,
        email: str,
        password: str,
        device_name: str,
        fingerprint: str | None = None,
    ) -> AuthTokens:
        # Share the reset/verification lock: an old-password login must not
        # mint a new session after a concurrent password reset revoked them.
        with self._challenge_lock:
            return self._login_locked(
                db, email=email, password=password, device_name=device_name, fingerprint=fingerprint,
            )

    def _login_locked(
        self,
        db: Session,
        *,
        email: str,
        password: str,
        device_name: str,
        fingerprint: str | None = None,
    ) -> AuthTokens:
        normalized_email = self._email(email)
        if self._is_login_locked(normalized_email):
            raise AuthError("Too many failed login attempts. Try again later.")
        user = self._challenge_user(db, normalized_email)
        if user is None:
            self._record_failed_login(normalized_email)
            raise AuthError("Invalid email or password", code="invalid_credentials")
        try:
            self.hasher.verify(user.password_hash, password)
        except (VerifyMismatchError, InvalidHashError):
            self._record_failed_login(normalized_email)
            self.audit.record(
                db,
                action="auth.login",
                user_public_id=user.public_id,
                resource="session",
                outcome="denied",
            )
            raise AuthError("Invalid email or password", code="invalid_credentials")
        self._require_activated(user)
        if self.hasher.check_needs_rehash(user.password_hash):
            user.password_hash = self.hasher.hash(password)
        tokens = self._new_session(db, user, device_name=device_name, fingerprint=fingerprint)
        self.audit.record(db, action="auth.login", user_public_id=user.public_id, resource="session", commit=False)
        db.commit()
        self._clear_failed_logins(normalized_email)
        return tokens

    def refresh(self, db: Session, refresh_token: str) -> AuthTokens:
        with self._challenge_lock:
            return self._refresh_locked(db, refresh_token)

    def _refresh_locked(self, db: Session, refresh_token: str) -> AuthTokens:
        token_hash = _hash_token(refresh_token)
        session = db.scalar(select(SessionRecord).where(SessionRecord.refresh_token_hash == token_hash))
        now = datetime.now(timezone.utc)
        if session is None or session.revoked_at is not None or _utc(session.expires_at) <= now:
            raise AuthError("Refresh token is invalid or expired")
        # Lock in the same user->session order as reset/login to avoid a
        # password-reset race (and PostgreSQL cross-worker deadlocks).
        user = db.scalar(select(UserRecord).where(UserRecord.public_id == session.user_public_id).with_for_update().execution_options(populate_existing=True))
        if user is None:
            raise AuthError("Account is unavailable")
        self._require_activated(user)
        session = db.scalar(select(SessionRecord).where(SessionRecord.refresh_token_hash == token_hash).with_for_update().execution_options(populate_existing=True))
        if session is None or session.revoked_at is not None or _utc(session.expires_at) <= now:
            raise AuthError("Refresh token is invalid or expired")
        new_refresh = secrets.token_urlsafe(48)
        session.refresh_token_hash = _hash_token(new_refresh)
        session.last_seen_at = now
        access = self._access_token(user.public_id, session.session_id, now)
        db.commit()
        return self._tokens(user, session, access, new_refresh)

    def revoke_session(self, db: Session, *, user_public_id: str, session_id: str) -> bool:
        session = db.scalar(
            select(SessionRecord).where(
                SessionRecord.session_id == session_id,
                SessionRecord.user_public_id == user_public_id,
            )
        )
        if session is None:
            return False
        if session.revoked_at is None:
            session.revoked_at = datetime.now(timezone.utc)
            self.audit.record(
                db,
                action="auth.session_revoke",
                user_public_id=user_public_id,
                resource=session_id,
                commit=False,
            )
            db.commit()
        return True

    def revoke_refresh_token(self, db: Session, refresh_token: str) -> bool:
        session = db.scalar(select(SessionRecord).where(SessionRecord.refresh_token_hash == _hash_token(refresh_token)))
        if session is None:
            return False
        if session.revoked_at is None:
            session.revoked_at = datetime.now(timezone.utc)
            self.audit.record(
                db,
                action="auth.logout",
                user_public_id=session.user_public_id,
                resource=session.session_id,
                commit=False,
            )
            db.commit()
        return True

    def revoke_all_sessions(self, db: Session, *, user_public_id: str) -> int:
        now = datetime.now(timezone.utc)
        rows = list(db.scalars(select(SessionRecord).where(
            SessionRecord.user_public_id == user_public_id,
            SessionRecord.revoked_at.is_(None),
        )))
        for row in rows:
            row.revoked_at = now
        self.audit.record(
            db,
            action="auth.logout_all",
            user_public_id=user_public_id,
            resource="sessions",
            metadata={"revoked_count": len(rows)},
            commit=False,
        )
        db.commit()
        return len(rows)

    def list_sessions(self, db: Session, *, user_public_id: str, current_session_id: str) -> list[SessionInfo]:
        now = datetime.now(timezone.utc)
        rows = list(
            db.scalars(
                select(SessionRecord)
                .where(
                    SessionRecord.user_public_id == user_public_id,
                    SessionRecord.revoked_at.is_(None),
                    SessionRecord.expires_at > now,
                )
                .order_by(SessionRecord.last_seen_at.desc())
            )
        )
        return [
            SessionInfo(
                session_id=row.session_id,
                device_name=row.device_name,
                created_at=_utc(row.created_at),
                last_seen_at=_utc(row.last_seen_at),
                expires_at=_utc(row.expires_at),
                current=row.session_id == current_session_id,
            )
            for row in rows
        ]

    def request_email_verification(self, db: Session, email: str) -> None:
        normalized = self._email(email)
        with self._challenge_lock:
            user = self._challenge_user(db, normalized)
            if user is None or user.email_verified:
                return
            self._require_challenge_account(user)
            self._issue_challenge(db, user, "email_verification")

    def confirm_email_verification(
        self, db: Session, *, email: str, code: str, new_password: str, device_name: str,
        fingerprint: str | None = None,
    ) -> AuthTokens:
        self._validate_password(new_password)
        with self._challenge_lock:
            user = self._challenge_user(db, self._email(email))
            if user is None:
                raise AuthError("The code is invalid. Request a new code.", code="otp_invalid")
            self._require_challenge_account(user)
            if user.email_verified:
                raise AuthError("The code is invalid. Request a new code.", code="otp_invalid")
            self._consume_challenge(db, user, "email_verification", code)
            # The mailbox owner chooses the password at activation. A prior
            # registration using someone else's address cannot retain access.
            user.password_hash = self.hasher.hash(new_password)
            user.email_verified = True
            now = datetime.now(timezone.utc)
            user.updated_at = now
            db.execute(update(SessionRecord).where(
                SessionRecord.user_public_id == user.public_id, SessionRecord.revoked_at.is_(None),
            ).values(revoked_at=now))
            tokens = self._new_session(db, user, device_name=device_name, fingerprint=fingerprint)
            self.audit.record(
                db, action="auth.email_verified", user_public_id=user.public_id, resource="user", commit=False,
            )
            db.commit()
            return tokens

    def create_password_reset(self, db: Session, email: str) -> None:
        with self._challenge_lock:
            user = self._challenge_user(db, self._email(email))
            if user is None:
                return
            self._require_challenge_account(user)
            self._issue_challenge(db, user, "password_reset")

    def confirm_password_reset(self, db: Session, *, email: str, code: str, new_password: str) -> None:
        self._validate_password(new_password)
        with self._challenge_lock:
            user = self._challenge_user(db, self._email(email))
            if user is None:
                raise AuthError("The code is invalid. Request a new code.", code="otp_invalid")
            self._require_challenge_account(user)
            self._consume_challenge(db, user, "password_reset", code)
            now = datetime.now(timezone.utc)
            user.password_hash = self.hasher.hash(new_password)
            user.updated_at = now
            # Invalidate every previous recovery/verification token, including
            # legacy high-entropy resets, in the password/session transaction.
            db.execute(update(AccountTokenRecord).where(
                AccountTokenRecord.user_public_id == user.public_id,
                AccountTokenRecord.used_at.is_(None),
            ).values(used_at=now))
            db.execute(update(SessionRecord).where(
                SessionRecord.user_public_id == user.public_id,
                SessionRecord.revoked_at.is_(None),
            ).values(revoked_at=now))
            self.audit.record(
                db, action="auth.password_reset", user_public_id=user.public_id, resource="user", commit=False,
            )
            db.commit()

    @staticmethod
    def _challenge_user(db: Session, email: str) -> UserRecord | None:
        return db.scalar(select(UserRecord).where(UserRecord.email == email).with_for_update().execution_options(
            populate_existing=True,
        ))

    @staticmethod
    def _require_challenge_account(user: UserRecord) -> None:
        # Verification/reset never overrides an administrative suspension.
        if not user.is_active:
            raise AuthError("Account is unavailable.", code="account_unavailable", status_code=403)

    @staticmethod
    def _require_activated(user: UserRecord) -> None:
        if not user.is_active:
            raise AuthError("Account is unavailable.", code="account_unavailable", status_code=403)
        if user.email_verification_required and not user.email_verified:
            raise AuthError(
                "Verify your email before signing in. You can request another code.",
                code="email_verification_required", status_code=403,
            )

    def _issue_challenge(self, db: Session, user: UserRecord, purpose: AuthEmailPurpose) -> None:
        now = datetime.now(timezone.utc)
        previous = db.scalar(select(AccountTokenRecord).where(
            AccountTokenRecord.user_public_id == user.public_id,
            AccountTokenRecord.purpose == purpose,
        ).order_by(AccountTokenRecord.created_at.desc(), AccountTokenRecord.id.desc()).limit(1))
        if previous is not None and previous.sent_at is not None:
            remaining = self._resend_seconds - (now - _utc(previous.sent_at)).total_seconds()
            if remaining > 0:
                raise AuthError(
                    "Please wait before requesting another code.", code="otp_resend_limited",
                    status_code=429, retry_after=math.ceil(remaining),
                )
        challenge_id = str(uuid4())
        code = f"{secrets.randbelow(1_000_000):06d}"
        # A resend never accidentally reissues the immediately preceding code.
        while previous is not None and previous.challenge_id and hmac.compare_digest(
            previous.token_hash, self._code_hash(user.public_id, purpose, previous.challenge_id, code),
        ):
            code = f"{secrets.randbelow(1_000_000):06d}"
        try:
            db.execute(update(AccountTokenRecord).where(
                AccountTokenRecord.user_public_id == user.public_id,
                AccountTokenRecord.purpose == purpose,
                AccountTokenRecord.used_at.is_(None),
            ).values(used_at=now))
            record = AccountTokenRecord(
                token_hash=self._code_hash(user.public_id, purpose, challenge_id, code),
                user_public_id=user.public_id, purpose=purpose, challenge_id=challenge_id,
                created_at=now, expires_at=now + timedelta(minutes=self._challenge_minutes),
                used_at=None, sent_at=None, attempt_count=0,
            )
            db.add(record)
            db.flush()
            self.email_sender.send_auth_code(
                email=user.email, code=code, purpose=purpose, expires_minutes=self._challenge_minutes,
            )
            record.sent_at = datetime.now(timezone.utc)
            self.audit.record(
                db, action=f"auth.{purpose}_requested", user_public_id=user.public_id,
                resource="email", commit=False,
            )
            db.commit()
        except EmailDeliveryError as exc:
            db.rollback()
            raise AuthError(
                "The email could not be sent. Please retry.", code="email_delivery_failed", status_code=503,
            ) from exc
        except IntegrityError as exc:
            db.rollback()
            raise AuthError(
                "Another code request is in progress. Please retry shortly.",
                code="otp_resend_limited", status_code=429, retry_after=2,
            ) from exc

    def _consume_challenge(self, db: Session, user: UserRecord, purpose: str, code: str) -> None:
        record = db.scalar(select(AccountTokenRecord).where(
            AccountTokenRecord.user_public_id == user.public_id,
            AccountTokenRecord.purpose == purpose,
        ).order_by(AccountTokenRecord.created_at.desc(), AccountTokenRecord.id.desc()).limit(1))
        if record is None:
            raise AuthError("The code is invalid. Request a new code.", code="otp_invalid")
        if record.attempt_count >= self._max_code_attempts:
            raise AuthError(
                "Too many incorrect codes. Request a new code.", code="otp_attempts_exceeded", status_code=429,
            )
        if record.used_at is not None or record.sent_at is None or not record.challenge_id:
            raise AuthError("The code is invalid. Request a new code.", code="otp_invalid")
        now = datetime.now(timezone.utc)
        if _utc(record.expires_at) <= now:
            raise AuthError("The code has expired. Request a new code.", code="otp_expired")
        raw = code.strip()
        normalized = "".join(str(unicodedata.decimal(char)) for char in raw) if raw.isdecimal() else ""
        matches = len(normalized) == 6 and hmac.compare_digest(
            record.token_hash, self._code_hash(user.public_id, purpose, record.challenge_id, normalized),
        )
        if not matches:
            attempts = db.scalar(update(AccountTokenRecord).where(
                AccountTokenRecord.id == record.id, AccountTokenRecord.used_at.is_(None),
            ).values(attempt_count=AccountTokenRecord.attempt_count + 1).returning(AccountTokenRecord.attempt_count))
            if attempts is not None and attempts >= self._max_code_attempts:
                db.execute(update(AccountTokenRecord).where(AccountTokenRecord.id == record.id).values(used_at=now))
            db.commit()
            if attempts is not None and attempts >= self._max_code_attempts:
                raise AuthError(
                    "Too many incorrect codes. Request a new code.", code="otp_attempts_exceeded", status_code=429,
                )
            raise AuthError("The code is invalid. Try again or request a new code.", code="otp_invalid")
        consumed = db.scalar(update(AccountTokenRecord).where(
            AccountTokenRecord.id == record.id, AccountTokenRecord.used_at.is_(None),
            AccountTokenRecord.expires_at > now, AccountTokenRecord.attempt_count < self._max_code_attempts,
        ).values(used_at=now).returning(AccountTokenRecord.id).execution_options(synchronize_session="fetch"))
        if consumed is None:
            raise AuthError("The code is invalid. Request a new code.", code="otp_invalid")

    def _code_hash(self, user_id: str, purpose: str, challenge_id: str, code: str) -> str:
        value = f"goldbrain-auth-code:{user_id}:{purpose}:{challenge_id}:{code}"
        return hmac.new(self.settings.jwt_secret.encode(), value.encode(), hashlib.sha256).hexdigest()

    def resolve_identity(self, db: Session, token: str) -> Identity:
        payload = decode_access_token(token, self.settings)
        user_id = str(payload.get("sub") or "")
        session_id = str(payload.get("sid") or "")
        if not user_id or not session_id:
            raise AuthError("Access token is invalid")
        user = db.scalar(select(UserRecord).where(UserRecord.public_id == user_id))
        session = db.scalar(select(SessionRecord).where(SessionRecord.session_id == session_id))
        now = datetime.now(timezone.utc)
        if (
            user is None
            or not user.is_active
            or session is None
            or session.user_public_id != user_id
            or session.revoked_at is not None
            or _utc(session.expires_at) <= now
        ):
            raise AuthError("Session is invalid or expired")
        self._require_activated(user)
        session.last_seen_at = now
        db.commit()
        return Identity(user=user, session=session)

    def _new_session(
        self,
        db: Session,
        user: UserRecord,
        *,
        device_name: str,
        fingerprint: str | None,
    ) -> AuthTokens:
        self._require_activated(user)
        now = datetime.now(timezone.utc)
        refresh = secrets.token_urlsafe(48)
        session = SessionRecord(
            session_id=str(uuid4()),
            user_public_id=user.public_id,
            refresh_token_hash=_hash_token(refresh),
            device_name=(device_name.strip() or "GoldBrain client")[:160],
            client_fingerprint=(fingerprint or "")[:64] or None,
            created_at=now,
            last_seen_at=now,
            expires_at=now + timedelta(days=self.settings.refresh_token_days),
            revoked_at=None,
        )
        db.add(session)
        access = self._access_token(user.public_id, session.session_id, now)
        return self._tokens(user, session, access, refresh)

    def _access_token(self, user_id: str, session_id: str, now: datetime) -> str:
        payload = {
            "sub": user_id,
            "sid": session_id,
            "typ": "access",
            "iss": "goldbrain",
            "iat": int(now.timestamp()),
            "exp": int((now + timedelta(minutes=self.settings.access_token_minutes)).timestamp()),
        }
        return jwt.encode(payload, self.settings.jwt_secret, algorithm="HS256")

    def _tokens(self, user: UserRecord, session: SessionRecord, access: str, refresh: str) -> AuthTokens:
        return AuthTokens(
            access_token=access,
            refresh_token=refresh,
            expires_in_seconds=self.settings.access_token_minutes * 60,
            session_id=session.session_id,
            user=self.profile(user),
        )

    @staticmethod
    def profile(user: UserRecord) -> UserProfile:
        return UserProfile(
            public_id=user.public_id,
            email=user.email,
            display_name=user.display_name,
            role=user.role,
            email_verified=user.email_verified,
            mfa_enabled=user.mfa_enabled,
            created_at=_utc(user.created_at),
        )

    @staticmethod
    def _email(value: str) -> str:
        normalized = value.strip().lower()
        if len(normalized) > 320 or not EMAIL_RE.match(normalized):
            raise AuthError("A valid email address is required")
        return normalized

    @staticmethod
    def _validate_password(password: str) -> None:
        if len(password) < 10 or len(password) > 128:
            raise AuthError("Password must be between 10 and 128 characters")
        if not any(char.isalpha() for char in password) or not any(char.isdigit() for char in password):
            raise AuthError("Password must contain at least one letter and one number")

    @classmethod
    def _is_login_locked(cls, email: str) -> bool:
        cutoff = time.monotonic() - cls._failed_window_seconds
        with cls._failed_logins_lock:
            attempts = [stamp for stamp in cls._failed_logins.get(email, []) if stamp >= cutoff]
            cls._failed_logins[email] = attempts
            return len(attempts) >= cls._max_failed_logins

    @classmethod
    def _record_failed_login(cls, email: str) -> None:
        now = time.monotonic()
        cutoff = now - cls._failed_window_seconds
        with cls._failed_logins_lock:
            attempts = [stamp for stamp in cls._failed_logins.get(email, []) if stamp >= cutoff]
            attempts.append(now)
            cls._failed_logins[email] = attempts

    @classmethod
    def _clear_failed_logins(cls, email: str) -> None:
        with cls._failed_logins_lock:
            cls._failed_logins.pop(email, None)


def decode_access_token(token: str, settings: Settings) -> dict:
    try:
        payload = jwt.decode(
            token,
            settings.jwt_secret,
            algorithms=["HS256"],
            issuer="goldbrain",
            options={"require": ["exp", "iat", "sub", "sid", "typ"]},
        )
    except jwt.PyJWTError as exc:
        raise AuthError("Access token is invalid or expired") from exc
    if payload.get("typ") != "access":
        raise AuthError("Access token type is invalid")
    return payload


def _hash_token(value: str) -> str:
    return hashlib.sha256(value.encode()).hexdigest()


def _utc(value: datetime) -> datetime:
    if value.tzinfo is None:
        return value.replace(tzinfo=timezone.utc)
    return value.astimezone(timezone.utc)
