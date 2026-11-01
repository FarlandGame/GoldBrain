"""Synthetic email capture used only by authentication tests."""
from app.schemas.auth import AuthTokens
from app.services.auth import AuthService
from app.services.auth_email import AuthEmailSender, EmailDeliveryError
from sqlalchemy.orm import Session


class CapturingEmailSender(AuthEmailSender):
    def __init__(self) -> None:
        self.messages: list[dict[str, str | int]] = []
        self.fail = False

    def send_auth_code(self, *, email: str, code: str, purpose: str, expires_minutes: int) -> None:
        if self.fail:
            raise EmailDeliveryError("Synthetic delivery failure")
        self.messages.append({"email": email, "code": code, "purpose": purpose, "expires_minutes": expires_minutes})

    def code_for(self, email: str, purpose: str) -> str:
        return str(next(item["code"] for item in reversed(self.messages) if item["email"] == email and item["purpose"] == purpose))


def register_verified(auth: AuthService, db: Session, sender: CapturingEmailSender, **payload: str) -> AuthTokens:
    auth.register(db, **payload)
    return auth.confirm_email_verification(
        db, email=payload["email"].strip().lower(),
        code=sender.code_for(payload["email"].strip().lower(), "email_verification"),
        new_password=payload["password"],
        device_name=payload["device_name"],
    )
