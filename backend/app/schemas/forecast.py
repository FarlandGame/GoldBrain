from __future__ import annotations

from datetime import datetime

from app.schemas.common import ApiModel


class ForecastRequest(ApiModel):
    symbol: str
    horizon: str = "1h"
    timeframe: str = "1h"
    persist: bool = True


class ForecastResponse(ApiModel):
    forecast_id: str
    symbol: str
    timeframe: str
    horizon: str
    direction: str
    anchor_price: float
    point_estimate: float
    lower_bound: float
    upper_bound: float
    confidence_score: int
    probability_up: float
    data_quality: int
    signal: str
    signal_quality: str
    trade_allowed: bool
    decision_reasons: list[str]
    model_version: str
    feature_version: str
    evidence_fingerprint: str
    calibration_status: str
    generated_at: datetime
    target_at: datetime
    reasons: list[str]
    model_breakdown: dict[str, float | str | int | None]
    evidence: dict[str, object] = {}


class ForecastEvaluationSummary(ApiModel):
    evaluated: int
    expired: int
    pending: int


class ForecastMetrics(ApiModel):
    symbol: str
    horizon: str
    sample_count: int
    independent_sample_count: int
    mean_absolute_error: float | None
    mean_absolute_percentage_error: float | None
    directional_hit_rate: float | None
    interval_hit_rate: float | None
    brier_score: float | None
    calibration_status: str
    rmse: float | None = None
    average_confidence: float | None = None
    strong_signal_accuracy: float | None = None
    baseline_directional_hit_rate: float | None = None


class BacktestRequest(ApiModel):
    symbol: str
    horizon: str = "1h"
    timeframe: str = "1h"
    minimum_train_points: int = 80
    max_steps: int = 180


class BacktestResponse(ApiModel):
    symbol: str
    horizon: str
    timeframe: str
    sample_count: int
    mean_absolute_error: float | None
    mean_absolute_percentage_error: float | None
    directional_hit_rate: float | None
    interval_hit_rate: float | None
    baseline_mean_absolute_percentage_error: float | None
    notes: list[str]
