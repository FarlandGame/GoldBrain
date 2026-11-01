from __future__ import annotations

from functools import lru_cache
from pathlib import Path

from pydantic import Field, SecretStr, field_validator, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict

BACKEND_DIR = Path(__file__).resolve().parents[2]


class Settings(BaseSettings):
    """Runtime configuration for the private-alpha backend.

    Secrets live in environment variables or backend/.env only. They are never
    shipped with the Flutter application.
    """

    model_config = SettingsConfigDict(
        env_file=BACKEND_DIR / ".env",
        env_file_encoding="utf-8",
        env_prefix="GOLDBRAIN_",
        case_sensitive=False,
        extra="ignore",
        # Startup validation tracebacks must not echo environment secrets.
        hide_input_in_errors=True,
    )

    app_name: str = "GoldBrain API"
    app_version: str = "0.3.0-private-beta"
    environment: str = "development"
    debug: bool = True
    api_v1_prefix: str = "/api/v1"

    database_url: str = "sqlite:///./data/goldbrain.db"
    auto_create_tables: bool = True
    redis_url: str = "redis://localhost:6379/0"
    private_api_key: str = ""
    jwt_secret: str = "dev-only-change-me"
    access_token_minutes: int = 15
    refresh_token_days: int = 30
    smtp_host: str = ""
    smtp_port: int = 465
    smtp_username: str = ""
    smtp_password: SecretStr = SecretStr("")
    smtp_from_email: str = ""
    smtp_from_name: str = "GoldBrain"
    smtp_security: str = "ssl"
    smtp_timeout_seconds: float = 10.0
    rate_limit_per_minute: int = 120
    cors_origins: str = "http://localhost:3000,http://127.0.0.1:3000"

    navasan_api_key: str = Field(default="", validation_alias="NAVASAN_API_KEY")
    coingecko_demo_api_key: str = Field(default="", validation_alias="COINGECKO_DEMO_API_KEY")
    coingecko_base_url: str = "https://api.coingecko.com/api/v3/"
    coingecko_min_quote_interval_seconds: int = 60
    navasan_base_url: str = "https://api.navasan.tech/"
    # Free access allows 120 requests/month and updates about every 2 hours.
    # Reserve room for deliberate history/diagnostic calls during development.
    navasan_min_quote_interval_seconds: int = 28800
    navasan_monthly_request_budget: int = 90
    wallex_base_url: str = "https://api.wallex.ir/"
    nobitex_base_url: str = "https://api.nobitex.ir/"
    zarix_base_url: str = "https://zarix.online/api/"
    gold_api_base_url: str = "https://api.gold-api.com/"

    ai_api_key: str = Field(default="", validation_alias="GAPGPT_API_KEY")
    ai_base_url: str = Field(default="https://api.gapgpt.app/v1", validation_alias="GAPGPT_BASE_URL")
    ai_model: str = Field(default="gpt-4o", validation_alias="GAPGPT_MODEL")
    market_timeout_seconds: float = 12.0
    market_cache_seconds: int = 120
    market_max_quote_age_seconds: int = 300
    market_collection_interval_seconds: int = 60
    wallex_rate_limit_per_minute: int = 120
    nobitex_rate_limit_per_minute: int = 60
    navasan_rate_limit_per_minute: int = 60

    @field_validator("api_v1_prefix")
    @classmethod
    def normalize_prefix(cls, value: str) -> str:
        value = value.strip()
        if not value.startswith("/"):
            value = f"/{value}"
        return value.rstrip("/") or "/api/v1"

    @field_validator("environment")
    @classmethod
    def normalize_environment(cls, value: str) -> str:
        normalized = value.strip().lower()
        if normalized not in {"development", "test", "staging", "production"}:
            raise ValueError("environment must be development, test, staging or production")
        return normalized

    @field_validator("market_timeout_seconds")
    @classmethod
    def validate_timeout(cls, value: float) -> float:
        if value <= 0 or value > 60:
            raise ValueError("market_timeout_seconds must be between 0 and 60")
        return value

    @field_validator("market_cache_seconds")
    @classmethod
    def validate_cache_seconds(cls, value: int) -> int:
        if value < 0 or value > 3600:
            raise ValueError("market_cache_seconds must be between 0 and 3600")
        return value

    @field_validator("market_max_quote_age_seconds")
    @classmethod
    def validate_quote_age_seconds(cls, value: int) -> int:
        if value < 30 or value > 86400:
            raise ValueError("market_max_quote_age_seconds must be between 30 and 86400")
        return value

    @field_validator("market_collection_interval_seconds")
    @classmethod
    def validate_collection_interval(cls, value: int) -> int:
        if value < 30 or value > 3600:
            raise ValueError("market_collection_interval_seconds must be between 30 and 3600")
        return value
    @field_validator("access_token_minutes")
    @classmethod
    def validate_access_minutes(cls, value: int) -> int:
        if value < 5 or value > 120:
            raise ValueError("access_token_minutes must be between 5 and 120")
        return value

    @field_validator("refresh_token_days")
    @classmethod
    def validate_refresh_days(cls, value: int) -> int:
        if value < 1 or value > 365:
            raise ValueError("refresh_token_days must be between 1 and 365")
        return value

    @field_validator("smtp_security")
    @classmethod
    def validate_smtp_security(cls, value: str) -> str:
        normalized = value.strip().lower()
        if normalized not in {"ssl", "starttls"}:
            raise ValueError("smtp_security must be ssl or starttls")
        return normalized

    @field_validator("smtp_port")
    @classmethod
    def validate_smtp_port(cls, value: int) -> int:
        if not 1 <= value <= 65535:
            raise ValueError("smtp_port must be between 1 and 65535")
        return value

    @field_validator("smtp_timeout_seconds")
    @classmethod
    def validate_smtp_timeout(cls, value: float) -> float:
        if not 0 < value <= 60:
            raise ValueError("smtp_timeout_seconds must be between 0 and 60")
        return value

    @field_validator("rate_limit_per_minute")
    @classmethod
    def validate_rate_limit(cls, value: int) -> int:
        if value < 10 or value > 10000:
            raise ValueError("rate_limit_per_minute must be between 10 and 10000")
        return value

    @model_validator(mode="after")
    def validate_production_secrets(self) -> "Settings":
        if self.environment == "production" and not self.private_api_key.strip():
            raise ValueError("GOLDBRAIN_PRIVATE_API_KEY is required in production")
        if self.environment == "production" and (
            not self.jwt_secret.strip() or self.jwt_secret == "dev-only-change-me"
        ):
            raise ValueError("GOLDBRAIN_JWT_SECRET must be set to a strong production secret")
        if self.environment == "production" and self.auto_create_tables:
            raise ValueError("GOLDBRAIN_AUTO_CREATE_TABLES must be false in production; run Alembic migrations")
        return self

    @property
    def parsed_cors_origins(self) -> list[str]:
        return [item.strip() for item in self.cors_origins.split(",") if item.strip()]


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    return Settings()
