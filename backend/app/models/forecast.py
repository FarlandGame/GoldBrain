from __future__ import annotations

from datetime import datetime, timezone

from sqlalchemy import JSON, Boolean, DateTime, Index, Integer, Numeric, String, event
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base


class ModelVersionRecord(Base):
    __tablename__ = "model_versions"

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    version: Mapped[str] = mapped_column(String(80), unique=True)
    model_name: Mapped[str] = mapped_column(String(80))
    metadata_json: Mapped[dict] = mapped_column(JSON, default=dict)
    active: Mapped[bool] = mapped_column(Boolean, default=False, index=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc)
    )


class ForecastRecord(Base):
    """Immutable forecast audit record.

    A forecast is stored before its target time. Outcomes are written into a
    separate evaluation record so failed predictions cannot be overwritten.
    """

    __tablename__ = "forecast_records"
    __table_args__ = (Index("ix_forecast_symbol_target", "symbol", "target_at"),)

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    forecast_id: Mapped[str] = mapped_column(String(96), unique=True, index=True)
    symbol: Mapped[str] = mapped_column(String(24), index=True)
    timeframe: Mapped[str] = mapped_column(String(12), default="1h")
    horizon: Mapped[str] = mapped_column(String(16), index=True)
    direction: Mapped[str] = mapped_column(String(16))
    anchor_price: Mapped[float] = mapped_column(Numeric(38, 18, asdecimal=False))
    point_estimate: Mapped[float] = mapped_column(Numeric(38, 18, asdecimal=False))
    lower_bound: Mapped[float] = mapped_column(Numeric(38, 18, asdecimal=False))
    upper_bound: Mapped[float] = mapped_column(Numeric(38, 18, asdecimal=False))
    confidence_score: Mapped[int] = mapped_column(Integer)
    probability_up: Mapped[float] = mapped_column(Numeric(38, 12, asdecimal=False))
    data_quality: Mapped[int] = mapped_column(Integer)
    signal: Mapped[str] = mapped_column(String(16), default="no_trade")
    signal_quality: Mapped[str] = mapped_column(String(16), default="unverified")
    trade_allowed: Mapped[bool] = mapped_column(Boolean, default=False)
    decision_reasons: Mapped[list[str] | None] = mapped_column(JSON, nullable=True)
    reasons: Mapped[list[str] | None] = mapped_column(JSON, nullable=True)
    model_breakdown: Mapped[dict[str, float | str | int | None] | None] = mapped_column(JSON, nullable=True)
    model_version: Mapped[str] = mapped_column(String(80))
    feature_version: Mapped[str] = mapped_column(String(40))
    evidence_fingerprint: Mapped[str] = mapped_column(String(80), index=True)
    calibration_status: Mapped[str] = mapped_column(String(24), default="provisional")
    generated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), index=True)
    target_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), index=True)
    input_key: Mapped[str | None] = mapped_column(String(128), unique=True, nullable=True)
    evidence_manifest: Mapped[dict | None] = mapped_column(JSON, nullable=True)


@event.listens_for(ForecastRecord, "before_update")
def _reject_forecast_mutation(mapper, connection, target) -> None:
    """Prevent changing forecast inputs/outcomes after ledger insertion.

    Explanation fields remain nullable and may be backfilled for legacy rows;
    all values used for prediction and evaluation are immutable.
    """
    from sqlalchemy import inspect

    state = inspect(target)
    immutable = {
        "forecast_id", "symbol", "timeframe", "horizon", "direction", "anchor_price",
        "point_estimate", "lower_bound", "upper_bound", "confidence_score", "probability_up",
        "data_quality", "signal", "signal_quality", "trade_allowed", "model_version",
        "feature_version", "evidence_fingerprint", "calibration_status", "generated_at", "target_at",
        "input_key", "evidence_manifest",
    }
    changed = [name for name in immutable if state.attrs[name].history.has_changes()]
    if changed:
        raise ValueError("Forecast records are immutable after creation.")


class ForecastEvaluationRecord(Base):
    __tablename__ = "forecast_evaluations"
    __table_args__ = (Index("ix_forecast_eval_target", "symbol", "target_at"),)

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    forecast_id: Mapped[str] = mapped_column(String(96), unique=True, index=True)
    symbol: Mapped[str] = mapped_column(String(24), index=True)
    horizon: Mapped[str] = mapped_column(String(16), index=True)
    target_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    actual_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    actual_price: Mapped[float] = mapped_column(Numeric(38, 18, asdecimal=False))
    absolute_error: Mapped[float] = mapped_column(Numeric(38, 18, asdecimal=False))
    absolute_percentage_error: Mapped[float] = mapped_column(Numeric(38, 12, asdecimal=False))
    direction_hit: Mapped[bool] = mapped_column(Boolean)
    interval_hit: Mapped[bool] = mapped_column(Boolean)
    evaluated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc)
    )
    actual_provider: Mapped[str | None] = mapped_column(String(40), nullable=True)
    actual_currency: Mapped[str | None] = mapped_column(String(12), nullable=True)
    actual_unit: Mapped[str | None] = mapped_column(String(24), nullable=True)
    actual_quality_status: Mapped[str | None] = mapped_column(String(16), nullable=True)
    actual_evidence_id: Mapped[int | None] = mapped_column(nullable=True)
    actual_evidence_timestamp: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    confidence_score: Mapped[int | None] = mapped_column(Integer, nullable=True)
    probability_up: Mapped[float | None] = mapped_column(Numeric(38, 12, asdecimal=False), nullable=True)
