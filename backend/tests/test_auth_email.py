from __future__ import annotations

import smtplib
import ssl
from datetime import datetime, timezone
from email.message import EmailMessage
from email.utils import parsedate_to_datetime
from unittest.mock import MagicMock

import pytest
from pydantic import SecretStr

from app.core.config import Settings
from app.services.auth_email import AuthEmailPurpose, AuthEmailSender, EmailDeliveryError


def _settings(**overrides: object) -> Settings:
    values: dict[str, object] = {
        "_env_file": None,
        "environment": "test",
        "auto_create_tables": False,
        "smtp_host": "smtp.example.com",
        "smtp_port": 465,
        "smtp_username": "mailer@example.com",
        "smtp_password": SecretStr("synthetic-test-password"),
        "smtp_from_email": "mailer@example.com",
        "smtp_from_name": "GoldBrain",
        "smtp_security": "ssl",
        "smtp_timeout_seconds": 10,
    }
    values.update(overrides)
    return Settings(**values)


def _mock_connection(monkeypatch: pytest.MonkeyPatch, name: str) -> tuple[MagicMock, MagicMock]:
    smtp = MagicMock()
    smtp.send_message.return_value = {}
    constructor = MagicMock()
    constructor.return_value.__enter__.return_value = smtp
    monkeypatch.setattr(f"app.services.auth_email.smtplib.{name}", constructor)
    return constructor, smtp


@pytest.mark.parametrize(
    ("purpose", "subject_fragment", "body_fragment"),
    [
        ("email_verification", "تأیید ایمیل", "فعال‌سازی"),
        ("password_reset", "بازیابی رمز عبور", "تغییر رمز عبور"),
    ],
)
def test_ssl_delivery_uses_authenticated_tls_and_persian_email(
    monkeypatch: pytest.MonkeyPatch, purpose: AuthEmailPurpose, subject_fragment: str, body_fragment: str,
    caplog: pytest.LogCaptureFixture,
) -> None:
    constructor, smtp = _mock_connection(monkeypatch, "SMTP_SSL")
    plaintext = MagicMock(side_effect=AssertionError("Unencrypted SMTP must not be used"))
    monkeypatch.setattr("app.services.auth_email.smtplib.SMTP", plaintext)
    sender = AuthEmailSender(_settings())

    sender.send_auth_code(
        email="recipient@example.com", code="012345", purpose=purpose, expires_minutes=10,
    )

    kwargs = constructor.call_args.kwargs
    assert kwargs["host"] == "smtp.example.com"
    assert kwargs["port"] == 465
    assert kwargs["timeout"] == 10
    assert isinstance(kwargs["context"], ssl.SSLContext)
    assert kwargs["context"].check_hostname is True
    assert kwargs["context"].verify_mode == ssl.CERT_REQUIRED
    smtp.login.assert_called_once_with("mailer@example.com", "synthetic-test-password")
    smtp.starttls.assert_not_called()
    smtp.set_debuglevel.assert_not_called()
    message = smtp.send_message.call_args.args[0]
    assert isinstance(message, EmailMessage)
    assert str(message["From"]) == "GoldBrain <mailer@example.com>"
    assert str(message["To"]) == "recipient@example.com"
    assert subject_fragment in str(message["Subject"])
    assert message.get_content_charset() == "utf-8"
    assert "012345" in message.get_content()
    assert "10 دقیقه" in message.get_content()
    assert body_fragment in message.get_content()
    assert smtp.send_message.call_args.kwargs == {
        "from_addr": "mailer@example.com", "to_addrs": ["recipient@example.com"],
    }
    assert "012345" not in caplog.text
    assert "recipient@example.com" not in caplog.text
    assert "synthetic-test-password" not in caplog.text


def test_starttls_happens_before_credentials_and_message(monkeypatch: pytest.MonkeyPatch) -> None:
    constructor, smtp = _mock_connection(monkeypatch, "SMTP")
    ssl_constructor = MagicMock(side_effect=AssertionError("Wrong TLS transport"))
    monkeypatch.setattr("app.services.auth_email.smtplib.SMTP_SSL", ssl_constructor)

    AuthEmailSender(_settings(smtp_security="starttls", smtp_port=587)).send_auth_code(
        email="recipient@example.com", code="654321", purpose="password_reset", expires_minutes=15,
    )

    assert constructor.call_args.kwargs == {"host": "smtp.example.com", "port": 587, "timeout": 10}
    assert [call[0] for call in smtp.mock_calls] == ["ehlo", "starttls", "ehlo", "login", "send_message"]
    context = smtp.starttls.call_args.kwargs["context"]
    assert context.check_hostname is True
    assert context.verify_mode == ssl.CERT_REQUIRED


@pytest.mark.parametrize(
    ("failure", "stage"),
    [
        (smtplib.SMTPAuthenticationError(535, b"synthetic-test-password 012345 recipient@example.com"), "login"),
        (smtplib.SMTPRecipientsRefused({"recipient@example.com": (550, b"012345")}), "send_message"),
        (smtplib.SMTPDataError(451, b"private-provider-response 012345"), "send_message"),
        (TimeoutError("timeout 012345 recipient@example.com"), "connect"),
        (OSError("smtp.example.com synthetic-test-password"), "connect"),
    ],
)
def test_transport_failures_are_sanitized_and_never_logged(
    monkeypatch: pytest.MonkeyPatch, failure: Exception, stage: str, caplog: pytest.LogCaptureFixture,
) -> None:
    constructor, smtp = _mock_connection(monkeypatch, "SMTP_SSL")
    if stage == "connect":
        constructor.side_effect = failure
    else:
        getattr(smtp, stage).side_effect = failure

    with pytest.raises(EmailDeliveryError, match="delivery failed. Please retry") as caught:
        AuthEmailSender(_settings()).send_auth_code(
            email="recipient@example.com", code="012345", purpose="email_verification", expires_minutes=10,
        )

    assert caught.value.__suppress_context__ is True
    for sensitive in ("012345", "synthetic-test-password", "recipient@example.com", "smtp.example.com"):
        assert sensitive not in str(caught.value)
        assert sensitive not in caplog.text


def test_auth_messages_have_utc_dates_and_distinct_message_ids(monkeypatch: pytest.MonkeyPatch) -> None:
    _, smtp = _mock_connection(monkeypatch, "SMTP_SSL")
    sender = AuthEmailSender(_settings())
    before = datetime.now(timezone.utc).replace(microsecond=0)
    for purpose in ("email_verification", "password_reset"):
        sender.send_auth_code(
            email="recipient@example.com", code="012345", purpose=purpose, expires_minutes=15,
        )
    after = datetime.now(timezone.utc)
    messages = [call.args[0] for call in smtp.send_message.call_args_list]
    ids = [str(message["Message-ID"]) for message in messages]
    assert len(set(ids)) == 2
    for message, message_id in zip(messages, ids, strict=True):
        assert len(message.get_all("Message-ID")) == 1
        assert len(message.get_all("Date")) == 1
        assert message_id.startswith("<") and message_id.endswith("@example.com>")
        sent_at = parsedate_to_datetime(str(message["Date"]))
        assert sent_at.utcoffset().total_seconds() == 0
        assert before <= sent_at <= after


def test_starttls_failure_does_not_send_credentials(monkeypatch: pytest.MonkeyPatch) -> None:
    _, smtp = _mock_connection(monkeypatch, "SMTP")
    smtp.starttls.side_effect = smtplib.SMTPNotSupportedError("private-provider-response")

    with pytest.raises(EmailDeliveryError, match="delivery failed"):
        AuthEmailSender(_settings(smtp_security="starttls", smtp_port=587)).send_auth_code(
            email="recipient@example.com", code="012345", purpose="email_verification", expires_minutes=10,
        )

    smtp.login.assert_not_called()
    smtp.send_message.assert_not_called()


def test_single_recipient_rejection_is_not_reported_as_success(monkeypatch: pytest.MonkeyPatch) -> None:
    _, smtp = _mock_connection(monkeypatch, "SMTP_SSL")
    smtp.send_message.return_value = {"recipient@example.com": (550, b"private-provider-response")}

    with pytest.raises(EmailDeliveryError, match="delivery failed") as caught:
        AuthEmailSender(_settings()).send_auth_code(
            email="recipient@example.com", code="012345", purpose="email_verification", expires_minutes=10,
        )
    assert "recipient@example.com" not in str(caught.value)


@pytest.mark.parametrize("field", ["smtp_host", "smtp_username", "smtp_password", "smtp_from_email"])
def test_missing_configuration_fails_without_network(
    monkeypatch: pytest.MonkeyPatch, field: str,
) -> None:
    constructor, _ = _mock_connection(monkeypatch, "SMTP_SSL")

    with pytest.raises(EmailDeliveryError):
        AuthEmailSender(_settings(**{field: ""})).send_auth_code(
            email="recipient@example.com", code="012345", purpose="email_verification", expires_minutes=10,
        )

    constructor.assert_not_called()


@pytest.mark.parametrize(
    ("email", "settings_override"),
    [
        ("recipient@example.com\r\nBcc: victim@example.com", {}),
        ("recipient@example.com,victim@example.com", {}),
        ("Name <recipient@example.com>", {}),
        ("not-an-address", {}),
        ("recipient@example.com", {"smtp_from_email": "mailer@example.com\nBcc: victim@example.com"}),
        ("recipient@example.com", {"smtp_from_name": "GoldBrain\r\nBcc: victim@example.com"}),
    ],
)
def test_invalid_addresses_and_header_injection_are_rejected_before_network(
    monkeypatch: pytest.MonkeyPatch, email: str, settings_override: dict[str, object],
) -> None:
    constructor, _ = _mock_connection(monkeypatch, "SMTP_SSL")

    with pytest.raises(EmailDeliveryError, match="could not be prepared") as caught:
        AuthEmailSender(_settings(**settings_override)).send_auth_code(
            email=email, code="012345", purpose="email_verification", expires_minutes=10,
        )

    constructor.assert_not_called()
    assert email not in str(caught.value)


@pytest.mark.parametrize("code", ["12345", "۱۲۳۴۵۶", "012345\nInjected", "not-an-otp"])
def test_invalid_codes_are_not_sent(monkeypatch: pytest.MonkeyPatch, code: str) -> None:
    constructor, _ = _mock_connection(monkeypatch, "SMTP_SSL")
    with pytest.raises(EmailDeliveryError, match="could not be prepared"):
        AuthEmailSender(_settings()).send_auth_code(
            email="recipient@example.com", code=code, purpose="email_verification", expires_minutes=10,
        )
    constructor.assert_not_called()
