from __future__ import annotations

from datetime import datetime

from app.schemas.common import ApiModel


class AssetMetadata(ApiModel):
    symbol: str
    name: str
    asset_class: str
    quote_currency: str
    live_quote: bool
    forecast: bool


class AssetListResponse(ApiModel):
    assets: list[AssetMetadata]


class MarketQuote(ApiModel):
    asset: str | None = None
    symbol: str
    name: str
    currency: str
    price: float
    updated_at: datetime
    provider: str
    change_percent: float | None = None
    upstream_source: str | None = None
    unit: str = "unknown"
    market: str = "unknown"
    provider_timestamp: datetime | None = None
    received_at: datetime | None = None
    latency_ms: int | None = None
    freshness_status: str = "FRESH"
    # Canonical wire name for new clients; freshness_status is retained for
    # backwards compatibility with the existing Flutter parser.
    freshness: str | None = None
    data_quality_status: str = "VALID"
    quality_flags: list[str] = []
    fallback_from: str | None = None
    provider_spread_percent: float | None = None


class ProviderIssue(ApiModel):
    symbol: str
    message: str


class QuoteBatchResponse(ApiModel):
    requested_symbols: list[str]
    quotes: list[MarketQuote]
    issues: list[ProviderIssue]
    partial: bool


class Gold18MarketContext(ApiModel):
    gold18_price: float
    implied_gold18_price: float
    premium_percent: float
    premium_state: str
    gold_ounce_price: float
    tether_price: float
    observed_at: datetime


class MarketDataStatus(ApiModel):
    symbol: str
    status: str
    provider: str | None = None
    observed_at: datetime | None = None
    age_seconds: int | None = None
    freshness_status: str | None = None
    data_quality_status: str | None = None
    last_successful_update: datetime | None = None


class MarketDataStatusResponse(ApiModel):
    assets: list[MarketDataStatus]


class ProviderObservability(ApiModel):
    provider: str
    operation: str
    request_count: int
    success_count: int
    error_count: int
    success_rate: float
    error_rate: float
    average_latency_ms: float | None = None
    last_successful_update: datetime | None = None
    fallback_count: int


class MarketObservabilityResponse(ApiModel):
    window_minutes: int
    providers: list[ProviderObservability]
    market_age_seconds: dict[str, int | None] = {}
    last_successful_update: dict[str, datetime | None] = {}
    fallback_usage: int = 0
    gap_count: int = 0
    stale_data_count: int = 0


class DashboardForecastSummary(ApiModel):
    forecast_id: str
    direction: str
    point_estimate: float
    lower_bound: float
    upper_bound: float
    confidence_score: int
    signal: str
    signal_quality: str
    trade_allowed: bool
    generated_at: datetime
    target_at: datetime


class DashboardAssetOverview(ApiModel):
    symbol: str
    quote: MarketQuote | None = None
    data_status: MarketDataStatus
    forecast: DashboardForecastSummary | None = None


class DashboardOverviewResponse(ApiModel):
    generated_at: datetime
    assets: list[DashboardAssetOverview]
