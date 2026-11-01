from __future__ import annotations

import re
import smtplib
import ssl
from datetime import datetime, timezone
from email.errors import HeaderParseError
from email.headerregistry import Address
from email.message import EmailMessage
from email.utils import format_datetime, make_msgid
from typing import Literal

from app.core.config import Settings

AuthEmailPurpose = Literal["email_verification", "password_reset"]


class EmailDeliveryError(RuntimeError):
    """A safe delivery failure without credentials or a provider's response."""


def _mailbox(value: str) -> str:
    if not value or "\r" in value or "\n" in value:
        raise ValueError("Invalid email address")
    raw = value.strip()
    if len(raw) > 254 or not raw.isascii():
        raise ValueError("Invalid email address")
    address = Address(addr_spec=raw)
    if not address.username or not address.domain:
        raise ValueError("Invalid email address")
    return address.addr_spec


class AuthEmailSender:
    """Deliver authentication codes through authenticated, encrypted SMTP.

    SMTP responses and message contents must not be logged. An unconfigured
    service fails explicitly; it never pretends that an email was delivered.
    """

    def __init__(self, settings: Settings) -> None:
        self.settings = settings

    def send_auth_code(
        self,
        *,
        email: str,
        code: str,
        purpose: AuthEmailPurpose,
        expires_minutes: int,
    ) -> None:
        settings = self.settings
        password = settings.smtp_password.get_secret_value()
        host = settings.smtp_host.strip()
        username = settings.smtp_username.strip()
        security = settings.smtp_security
        if (
            not host
            or not username
            or not password
            or "\r" in host
            or "\n" in host
            or "\r" in username
            or "\n" in username
            or security not in {"ssl", "starttls"}
            or not 1 <= settings.smtp_port <= 65535
            or not 0 < settings.smtp_timeout_seconds <= 60
        ):
            raise EmailDeliveryError("Authentication email delivery is not configured.")

        try:
            recipient = _mailbox(email)
            sender = _mailbox(settings.smtp_from_email)
            sender_name = settings.smtp_from_name.strip()
            if "\r" in sender_name or "\n" in sender_name or len(sender_name) > 200:
                raise ValueError("Invalid sender name")
            if not re.fullmatch(r"[0-9]{6}", code) or not 1 <= expires_minutes <= 60:
                raise ValueError("Invalid authentication code")
            if purpose == "email_verification":
                subject = "کد تأیید ایمیل GoldBrain"
                action = "برای تأیید آدرس ایمیل و فعال‌سازی حساب GoldBrain"
            elif purpose == "password_reset":
                subject = "کد بازیابی رمز عبور GoldBrain"
                action = "برای تغییر رمز عبور حساب GoldBrain"
            else:
                raise ValueError("Invalid authentication email purpose")

            message = EmailMessage()
            message["From"] = Address(display_name=sender_name, addr_spec=sender)
            message["To"] = recipient
            message["Date"] = format_datetime(datetime.now(timezone.utc))
            message["Message-ID"] = make_msgid(domain=Address(addr_spec=sender).domain)
            message["Subject"] = subject
            message["Auto-Submitted"] = "auto-generated"
            message.set_content(
                f"سلام،\n\n{action}، این کد را در برنامه وارد کنید:\n\n"
                f"{code}\n\nاین کد تا {expires_minutes} دقیقه معتبر است.\n"
                "کد را با دیگران به اشتراک نگذارید.\n"
                "اگر این درخواست را شما ثبت نکرده‌اید، این ایمیل را نادیده بگیرید.\n\n"
                "GoldBrain\n",
                charset="utf-8",
            )
        except (ValueError, TypeError, HeaderParseError):
            raise EmailDeliveryError("Authentication email could not be prepared.") from None

        try:
            tls_context = ssl.create_default_context()
            connection: smtplib.SMTP
            if security == "ssl":
                connection = smtplib.SMTP_SSL(
                    host=host,
                    port=settings.smtp_port,
                    timeout=settings.smtp_timeout_seconds,
                    context=tls_context,
                )
            else:
                connection = smtplib.SMTP(
                    host=host,
                    port=settings.smtp_port,
                    timeout=settings.smtp_timeout_seconds,
                )
            with connection as smtp:
                if security == "starttls":
                    smtp.ehlo()
                    smtp.starttls(context=tls_context)
                    smtp.ehlo()
                smtp.login(username, password)
                rejected = smtp.send_message(message, from_addr=sender, to_addrs=[recipient])
                if rejected:
                    raise EmailDeliveryError("Authentication email delivery failed. Please retry.")
        except (smtplib.SMTPException, OSError):
            raise EmailDeliveryError("Authentication email delivery failed. Please retry.") from None
