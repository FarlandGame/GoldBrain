from __future__ import annotations

import hashlib
import math
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from statistics import NormalDist
from typing import Sequence

import numpy as np
from sklearn.ensemble import HistGradientBoostingRegressor
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.models.candle import MarketCandleRecord
from app.models.forecast import ForecastEvaluationRecord, ForecastRecord
from app.schemas.forecast import BacktestResponse, ForecastMetrics, ForecastResponse
from app.services.features import FEATURE_VERSION, FeatureEngine
from app.services.history import MarketHistoryService

MODEL_VERSION = "ensemble-v2.1"
HORIZONS: dict[str, timedelta] = {
    "15m": timedelta(minutes=15),
    "1h": timedelta(hours=1),
    "4h": timedelta(hours=4),
    "12h": timedelta(hours=12),
    "24h": timedelta(hours=24),
    "7d": timedelta(days=7),
    "30d": timedelta(days=30),
}


class ForecastError(ValueError):
    pass


@dataclass(frozen=True)
class _PredictionParts:
    projected_log_return: float
    baseline_log_return: float
    challenger_log_return: float | None
    challenger_weight: float
    uncertainty: float
    probability_up: float
    calibration_status: str
    breakdown: dict[str, float | str | int | None]


@dataclass(frozen=True)
class _SupervisedData:
    x: np.ndarray
    y: np.ndarray
    baseline: np.ndarray


class ForecastService:
    """Auditable champion/challenger forecasting for the private alpha.

    This is deliberately not marketed as a guaranteed trading signal. The
    baseline is always available with enough candles; the ML challenger joins
    only when there is enough leak-free training/validation history.
    """

    def __init__(self, history: MarketHistoryService | None = None) -> None:
        self.history = history or MarketHistoryService()
        self.features = FeatureEngine()

    def generate(
        self,
        db: Session,
        *,
        symbol: str,
        horizon: str,
        timeframe: str,
        persist: bool = True,
        now: datetime | None = None,
    ) -> ForecastResponse:
        symbol = symbol.strip().upper()
        horizon = horizon.strip().lower()
        timeframe = timeframe.strip().lower()
        horizon_delta = HORIZONS.get(horizon)
        if horizon_delta is None:
            raise ForecastError(f"Unsupported horizon: {horizon}")
        generated_at = _utc(now or datetime.now(timezone.utc))
        rows = self.history.get_candles(
            db,
            symbol,
            timeframe,
            limit=1500,
            closed_before=generated_at,
        )
        if len(rows) < self.features.minimum_points:
            raise ForecastError(
                f"Not enough {timeframe} history for {symbol}; "
                f"need at least {self.features.minimum_points} candles."
            )
        bars_ahead = _bars_for_horizon(rows, horizon_delta)
        if bars_ahead < 1:
            raise ForecastError("Selected timeframe is too coarse for this horizon.")
        snapshot = self.features.snapshot(rows)
        stale_rows = [row for row in rows if row.freshness_status in {"STALE", "UNAVAILABLE"}]
        invalid_rows = [row for row in rows if row.data_quality_status in {"INVALID", "SUSPECT"}]
        unverified_rows = [row for row in rows if row.data_quality_status == "UNVERIFIED"]
        closes = np.asarray([row.close for row in rows], dtype=float)
        parts = self._predict(closes, bars_ahead)
        anchor = float(closes[-1])
        point = anchor * math.exp(parts.projected_log_return)
        lower = anchor * math.exp(parts.projected_log_return - 1.2816 * parts.uncertainty)
        upper = anchor * math.exp(parts.projected_log_return + 1.2816 * parts.uncertainty)
        probability_up = min(0.995, max(0.005, parts.probability_up))
        direction_probability = max(probability_up, 1.0 - probability_up)
        neutral_threshold = max(parts.uncertainty * 0.12, 0.00035)
        if abs(parts.projected_log_return) <= neutral_threshold:
            direction = "neutral"
            confidence = int(min(80, round(snapshot.data_quality * 0.55 + 20)))
        elif parts.projected_log_return > 0:
            direction = "upward"
            confidence = int(min(92, round(direction_probability * 100 * 0.7 + snapshot.data_quality * 0.3)))
        else:
            direction = "downward"
            confidence = int(min(92, round(direction_probability * 100 * 0.7 + snapshot.data_quality * 0.3)))
        signal, signal_quality, trade_allowed, decision_reasons = _signal_decision(
            direction=direction,
            confidence=confidence,
            data_quality=snapshot.data_quality,
            calibration_status=parts.calibration_status,
            validation_directional_accuracy=parts.breakdown.get("validation_directional_accuracy"),
        )
        if stale_rows or invalid_rows or unverified_rows:
            signal, signal_quality, trade_allowed = "no_trade", "low", False
            decision_reasons = list(decision_reasons) + [
                "Forecast evidence is stale, unverified or invalid; trading and evaluation are gated."
            ]
        fingerprint = _fingerprint(rows, horizon, timeframe, bars_ahead)
        forecast_id = f"{symbol}-{horizon}-{generated_at.strftime('%Y%m%dT%H%M%S')}-{fingerprint[:12]}"
        response = ForecastResponse(
            forecast_id=forecast_id,
            symbol=symbol,
            timeframe=timeframe,
            horizon=horizon,
            direction=direction,
            anchor_price=anchor,
            point_estimate=point,
            lower_bound=lower,
            upper_bound=upper,
            confidence_score=confidence,
            probability_up=probability_up,
            data_quality=snapshot.data_quality,
            signal=signal,
            signal_quality=signal_quality,
            trade_allowed=trade_allowed,
            decision_reasons=decision_reasons,
            model_version=MODEL_VERSION,
            feature_version=FEATURE_VERSION,
            evidence_fingerprint=fingerprint,
            calibration_status=parts.calibration_status,
            generated_at=generated_at,
            target_at=generated_at + horizon_delta,
            reasons=list(snapshot.reasons),
            model_breakdown=parts.breakdown,
            evidence=_evidence_manifest(rows, model_version=MODEL_VERSION),
        )
        if persist:
            existing = db.scalar(
                select(ForecastRecord)
                .where(
                    ForecastRecord.symbol == response.symbol,
                    ForecastRecord.timeframe == response.timeframe,
                    ForecastRecord.horizon == response.horizon,
                    ForecastRecord.evidence_fingerprint == response.evidence_fingerprint,
                    ForecastRecord.model_version == response.model_version,
                )
                .order_by(ForecastRecord.generated_at.desc())
                .limit(1)
            )
            if existing is not None:
                # Reuse the immutable ledger identity while the underlying
                # candle evidence is unchanged. Repeated polling must not
                # inflate accuracy metrics with duplicate forecasts.
                return response.model_copy(
                    update={
                        "forecast_id": existing.forecast_id,
                        "direction": existing.direction,
                        "anchor_price": existing.anchor_price,
                        "point_estimate": existing.point_estimate,
                        "lower_bound": existing.lower_bound,
                        "upper_bound": existing.upper_bound,
                        "confidence_score": existing.confidence_score,
                        "probability_up": existing.probability_up,
                        "data_quality": existing.data_quality,
                        "signal": existing.signal,
                        "signal_quality": existing.signal_quality,
                        "trade_allowed": existing.trade_allowed,
                        "model_version": existing.model_version,
                        "feature_version": existing.feature_version,
                        "calibration_status": existing.calibration_status,
                        "generated_at": _utc(existing.generated_at),
                        "target_at": _utc(existing.target_at),
                    }
                )
            try:
                self._persist_forecast(db, response)
            except IntegrityError:
                # Two workers can generate the same immutable input concurrently.
                # The unique input key makes the second worker reuse the first row.
                db.rollback()
                existing = db.scalar(select(ForecastRecord).where(ForecastRecord.input_key == _input_key(response)))
                if existing is not None:
                    return _forecast_schema(existing)
                raise
        return response

    def evaluate_due(self, db: Session, *, now: datetime | None = None) -> tuple[int, int, int]:
        now = _utc(now or datetime.now(timezone.utc))
        forecasts = list(
            db.scalars(
                select(ForecastRecord)
                .where(ForecastRecord.target_at <= now)
                .order_by(ForecastRecord.target_at)
            )
        )
        evaluated_ids = set(db.scalars(select(ForecastEvaluationRecord.forecast_id)))
        evaluated = expired = pending = 0
        for forecast in forecasts:
            if forecast.forecast_id in evaluated_ids:
                continue
            horizon_delta = HORIZONS.get(forecast.horizon, timedelta(hours=1))
            tolerance = max(timedelta(minutes=30), horizon_delta / 2)
            rows = self.history.get_candles(
                db,
                forecast.symbol,
                forecast.timeframe,
                limit=50,
                before=_utc(forecast.target_at) + tolerance,
                closed_before=now,
            )
            evidence = forecast.evidence_manifest or {}
            evidence_providers = set(evidence.get("providers", [])) if isinstance(evidence, dict) else set()
            evidence_currency = next(iter(evidence.get("currencies", [])), None) if isinstance(evidence, dict) else None
            evidence_unit = next(iter(evidence.get("units", [])), None) if isinstance(evidence, dict) else None
            rows = [
                row for row in rows
                if row.data_quality_status not in {"INVALID", "SUSPECT", "UNVERIFIED"}
                and math.isfinite(row.close) and row.close > 0
                and (not evidence_providers or row.provider in evidence_providers)
                and (not evidence_currency or row.currency == evidence_currency)
                and (not evidence_unit or row.unit == evidence_unit)
            ]
            candidates = [
                row
                for row in rows
                if _utc(row.closed_at) >= _utc(forecast.target_at)
                and abs((_utc(row.closed_at) - _utc(forecast.target_at)).total_seconds()) <= tolerance.total_seconds()
                and row.freshness_status not in {"STALE", "UNAVAILABLE"}
            ]
            if not candidates:
                if now > _utc(forecast.target_at) + tolerance:
                    expired += 1
                else:
                    pending += 1
                continue
            actual_row = min(
                candidates,
                key=lambda row: abs((_utc(row.closed_at) - _utc(forecast.target_at)).total_seconds()),
            )
            actual = actual_row.close
            error = abs(actual - forecast.point_estimate)
            ape = error / actual * 100 if actual > 0 else 0.0
            actual_move = actual / forecast.anchor_price - 1.0
            neutral_band = max(
                (forecast.upper_bound - forecast.lower_bound) / forecast.anchor_price * 0.08,
                0.0005,
            )
            direction_hit = (
                actual_move > neutral_band
                if forecast.direction == "upward"
                else actual_move < -neutral_band
                if forecast.direction == "downward"
                else abs(actual_move) <= neutral_band
            )
            db.add(ForecastEvaluationRecord(
                    forecast_id=forecast.forecast_id,
                    symbol=forecast.symbol,
                    horizon=forecast.horizon,
                    target_at=_utc(forecast.target_at),
                    actual_at=_utc(actual_row.closed_at),
                    actual_price=actual,
                    absolute_error=error,
                    absolute_percentage_error=ape,
                    direction_hit=direction_hit,
                    interval_hit=forecast.lower_bound <= actual <= forecast.upper_bound,
                    evaluated_at=now,
                    actual_provider=actual_row.provider,
                    actual_currency=actual_row.currency,
                    actual_unit=actual_row.unit,
                    actual_quality_status=actual_row.data_quality_status,
                    actual_evidence_id=actual_row.id,
                    actual_evidence_timestamp=_utc(actual_row.provider_timestamp or actual_row.closed_at),
                    confidence_score=forecast.confidence_score,
                    probability_up=forecast.probability_up,
                ))
            try:
                db.commit()
            except IntegrityError:
                db.rollback()
                evaluated_ids.add(forecast.forecast_id)
                continue
            evaluated += 1
        return evaluated, expired, pending

    def latest(
        self,
        db: Session,
        *,
        symbol: str,
        horizon: str = "1h",
        timeframe: str = "1h",
    ) -> ForecastResponse:
        row = db.scalar(
            select(ForecastRecord)
            .where(
                ForecastRecord.symbol == symbol.strip().upper(),
                ForecastRecord.horizon == horizon.strip().lower(),
                ForecastRecord.timeframe == timeframe.strip().lower(),
            )
            .order_by(ForecastRecord.generated_at.desc())
            .limit(1)
        )
        if row is None:
            raise ForecastError("No persisted forecast is available for this market yet.")
        legacy_message = "This legacy forecast was created before explanations were persisted."
        return ForecastResponse(
            forecast_id=row.forecast_id,
            symbol=row.symbol,
            timeframe=row.timeframe,
            horizon=row.horizon,
            direction=row.direction,
            anchor_price=row.anchor_price,
            point_estimate=row.point_estimate,
            lower_bound=row.lower_bound,
            upper_bound=row.upper_bound,
            confidence_score=row.confidence_score,
            probability_up=row.probability_up,
            data_quality=row.data_quality,
            signal=row.signal,
            signal_quality=row.signal_quality,
            trade_allowed=row.trade_allowed,
            decision_reasons=list(row.decision_reasons or [legacy_message]),
            model_version=row.model_version,
            feature_version=row.feature_version,
            evidence_fingerprint=row.evidence_fingerprint,
            calibration_status=row.calibration_status,
            generated_at=_utc(row.generated_at),
            target_at=_utc(row.target_at),
            reasons=list(row.reasons or [legacy_message]),
            model_breakdown=dict(
                row.model_breakdown or {"explanation_status": "legacy-unavailable"}
            ),
            evidence=dict(row.evidence_manifest or {}),
        )

    def metrics(self, db: Session, *, symbol: str, horizon: str) -> ForecastMetrics:
        symbol = symbol.strip().upper()
        horizon = horizon.strip().lower()
        evaluations = list(
            db.scalars(
                select(ForecastEvaluationRecord)
                .where(
                    ForecastEvaluationRecord.symbol == symbol,
                    ForecastEvaluationRecord.horizon == horizon,
                )
                .order_by(ForecastEvaluationRecord.target_at.asc())
            )
        )
        if not evaluations:
            return ForecastMetrics(
                symbol=symbol,
                horizon=horizon,
                sample_count=0,
                independent_sample_count=0,
                mean_absolute_error=None,
                mean_absolute_percentage_error=None,
                directional_hit_rate=None,
                interval_hit_rate=None,
                brier_score=None,
                calibration_status="collecting-evidence",
                rmse=None,
                average_confidence=None,
                strong_signal_accuracy=None,
                baseline_directional_hit_rate=None,
            )
        horizon_delta = HORIZONS.get(horizon, timedelta(hours=1))
        independent: list[ForecastEvaluationRecord] = []
        last_target: datetime | None = None
        for item in evaluations:
            target = _utc(item.target_at)
            if last_target is None or target - last_target >= horizon_delta:
                independent.append(item)
                last_target = target
        forecasts_by_id = {
            item.forecast_id: item
            for item in db.scalars(
                select(ForecastRecord).where(
                    ForecastRecord.forecast_id.in_([item.forecast_id for item in independent])
                )
            )
        }
        n = len(independent)
        mae = sum(item.absolute_error for item in independent) / n
        mape = sum(item.absolute_percentage_error for item in independent) / n
        direction = sum(1 for item in independent if item.direction_hit) / n * 100
        interval = sum(1 for item in independent if item.interval_hit) / n * 100
        brier_terms: list[float] = []
        for item in independent:
            forecast = forecasts_by_id.get(item.forecast_id)
            if forecast is None:
                continue
            actual_up = 1.0 if item.actual_price > forecast.anchor_price else 0.0
            brier_terms.append((forecast.probability_up - actual_up) ** 2)
        brier = sum(brier_terms) / len(brier_terms) if brier_terms else None
        rmse = math.sqrt(sum(item.absolute_error ** 2 for item in independent) / n) if n else None
        confidences = [item.confidence_score for item in independent if item.confidence_score is not None]
        strong = [item for item in independent if item.confidence_score is not None and item.confidence_score >= 80]
        strong_accuracy = sum(item.direction_hit for item in strong) / len(strong) * 100 if strong else None
        baseline_hits = [
            item.actual_price >= forecast.anchor_price
            for item in independent
            if (forecast := forecasts_by_id.get(item.forecast_id)) is not None
        ]
        baseline_dir = sum(baseline_hits) / len(baseline_hits) * 100 if baseline_hits else None
        status = "measured" if n >= 30 else "provisional"
        return ForecastMetrics(
            symbol=symbol,
            horizon=horizon,
            sample_count=len(evaluations),
            independent_sample_count=n,
            mean_absolute_error=mae,
            mean_absolute_percentage_error=mape,
            directional_hit_rate=direction,
            interval_hit_rate=interval,
            brier_score=brier,
            calibration_status=status,
            rmse=rmse,
            average_confidence=sum(confidences) / len(confidences) if confidences else None,
            strong_signal_accuracy=strong_accuracy,
            baseline_directional_hit_rate=baseline_dir,
        )

    def backtest(
        self,
        db: Session,
        *,
        symbol: str,
        horizon: str,
        timeframe: str,
        minimum_train_points: int = 80,
        max_steps: int = 180,
    ) -> BacktestResponse:
        symbol = symbol.strip().upper()
        horizon = horizon.strip().lower()
        timeframe = timeframe.strip().lower()
        horizon_delta = HORIZONS.get(horizon)
        if horizon_delta is None:
            raise ForecastError(f"Unsupported horizon: {horizon}")
        rows = self.history.get_candles(
            db,
            symbol,
            timeframe,
            limit=2500,
            closed_before=datetime.now(timezone.utc),
        )
        if len(rows) < max(minimum_train_points, self.features.minimum_points) + 10:
            raise ForecastError("Not enough history for an out-of-sample backtest.")
        bars = _bars_for_horizon(rows, horizon_delta)
        closes = np.asarray([row.close for row in rows], dtype=float)
        data = self._supervised(closes, bars)
        if len(data.y) < max(60, minimum_train_points):
            raise ForecastError("Not enough supervised samples for this horizon/timeframe.")
        count = len(data.y)
        train_end = max(40, int(count * 0.70))
        calibration_end = max(train_end + 10, int(count * 0.85))
        if calibration_end >= count:
            raise ForecastError("Not enough holdout samples for backtesting.")
        model = self._fit_challenger(data.x[:train_end], data.y[:train_end])
        calibration_pred = model.predict(data.x[train_end:calibration_end])
        cal_y = data.y[train_end:calibration_end]
        cal_base = data.baseline[train_end:calibration_end]
        challenger_mae = float(np.mean(np.abs(calibration_pred - cal_y)))
        baseline_mae = float(np.mean(np.abs(cal_base - cal_y)))
        weight = _challenger_weight(baseline_mae, challenger_mae)
        residual_std = float(np.std(cal_y - (weight * calibration_pred + (1 - weight) * cal_base), ddof=1))
        residual_std = max(residual_std, 0.001)

        test_x = data.x[calibration_end:]
        test_y = data.y[calibration_end:]
        test_base = data.baseline[calibration_end:]
        test_challenger = model.predict(test_x)
        ensemble = weight * test_challenger + (1 - weight) * test_base
        if max_steps > 0 and len(test_y) > max_steps:
            test_y = test_y[-max_steps:]
            test_base = test_base[-max_steps:]
            ensemble = ensemble[-max_steps:]
        anchor_indices_start = len(closes) - len(test_y) - bars
        # Price-space metrics from log-return targets. Anchor alignment is
        # reconstructed from the tail used for the holdout set.
        predicted_prices: list[float] = []
        actual_prices: list[float] = []
        baseline_prices: list[float] = []
        direction_hits = interval_hits = 0
        for index, (pred_ret, actual_ret, base_ret) in enumerate(zip(ensemble, test_y, test_base)):
            anchor_idx = anchor_indices_start + index
            anchor = float(closes[anchor_idx])
            predicted = anchor * math.exp(float(pred_ret))
            actual = anchor * math.exp(float(actual_ret))
            baseline_price = anchor * math.exp(float(base_ret))
            predicted_prices.append(predicted)
            actual_prices.append(actual)
            baseline_prices.append(baseline_price)
            if (pred_ret > 0) == (actual_ret > 0):
                direction_hits += 1
            low = anchor * math.exp(float(pred_ret) - 1.2816 * residual_std)
            high = anchor * math.exp(float(pred_ret) + 1.2816 * residual_std)
            if low <= actual <= high:
                interval_hits += 1
        n = len(actual_prices)
        errors = [abs(p - a) for p, a in zip(predicted_prices, actual_prices)]
        apes = [error / actual * 100 for error, actual in zip(errors, actual_prices) if actual > 0]
        base_apes = [
            abs(pred - actual) / actual * 100
            for pred, actual in zip(baseline_prices, actual_prices)
            if actual > 0
        ]
        return BacktestResponse(
            symbol=symbol,
            horizon=horizon,
            timeframe=timeframe,
            sample_count=n,
            mean_absolute_error=sum(errors) / n if n else None,
            mean_absolute_percentage_error=sum(apes) / len(apes) if apes else None,
            directional_hit_rate=direction_hits / n * 100 if n else None,
            interval_hit_rate=interval_hits / n * 100 if n else None,
            baseline_mean_absolute_percentage_error=sum(base_apes) / len(base_apes) if base_apes else None,
            notes=[
                "Chronological 70/15/15 train-calibration-test split; test data is not used for fitting.",
                f"Challenger weight selected from calibration error: {weight:.2f}.",
                "Results are research metrics, not a profit guarantee or live-trading recommendation.",
            ],
        )

    def _predict(self, closes: np.ndarray, bars_ahead: int) -> _PredictionParts:
        current_features = self.features.vector(closes)
        baseline = _baseline_return(current_features, bars_ahead)
        data = self._supervised(closes, bars_ahead)
        challenger_prediction: float | None = None
        weight = 0.0
        residual_std = max(abs(float(current_features[1])) * math.sqrt(bars_ahead), 0.0015)
        calibration_status = "provisional"
        validation_count = 0
        validation_directional_accuracy: float | None = None
        challenger_mae: float | None = None
        baseline_mae: float | None = None
        if len(data.y) >= 80:
            split = max(50, int(len(data.y) * 0.8))
            if split < len(data.y) - 10:
                model = self._fit_challenger(data.x[:split], data.y[:split])
                validation_pred = model.predict(data.x[split:])
                validation_y = data.y[split:]
                validation_base = data.baseline[split:]
                challenger_mae = float(np.mean(np.abs(validation_pred - validation_y)))
                baseline_mae = float(np.mean(np.abs(validation_base - validation_y)))
                weight = _challenger_weight(baseline_mae, challenger_mae)
                residuals = validation_y - (weight * validation_pred + (1 - weight) * validation_base)
                if len(residuals) > 1:
                    residual_std = max(float(np.std(residuals, ddof=1)), 0.001)
                challenger_prediction = float(model.predict(current_features.reshape(1, -1))[0])
                validation_count = len(validation_y)
                validation_ensemble = weight * validation_pred + (1 - weight) * validation_base
                validation_directional_accuracy = float(
                    np.mean((validation_ensemble > 0) == (validation_y > 0)) * 100
                )
                calibration_status = "validation-based" if validation_count >= 30 else "provisional"
        projected = (
            baseline
            if challenger_prediction is None
            else (1 - weight) * baseline + weight * challenger_prediction
        )
        maximum_move = min(0.35, max(0.02, residual_std * 5.0))
        projected = float(np.clip(projected, -maximum_move, maximum_move))
        z = projected / max(residual_std, 1e-6)
        probability_up = NormalDist().cdf(z)
        return _PredictionParts(
            projected_log_return=projected,
            baseline_log_return=baseline,
            challenger_log_return=challenger_prediction,
            challenger_weight=weight,
            uncertainty=residual_std,
            probability_up=probability_up,
            calibration_status=calibration_status,
            breakdown={
                "baseline_log_return": baseline,
                "challenger_log_return": challenger_prediction,
                "challenger_weight": weight,
                "validation_samples": validation_count,
                "validation_directional_accuracy": validation_directional_accuracy,
                "baseline_validation_mae": baseline_mae,
                "challenger_validation_mae": challenger_mae,
                "uncertainty_log_return": residual_std,
            },
        )

    def _supervised(self, closes: np.ndarray, bars_ahead: int) -> _SupervisedData:
        x_rows: list[np.ndarray] = []
        y_rows: list[float] = []
        baseline_rows: list[float] = []
        minimum = self.features.minimum_points
        start = max(minimum, len(closes) - 900)
        for end in range(start, len(closes) - bars_ahead):
            history = closes[: end + 1]
            vector = self.features.vector(history)
            target_index = end + bars_ahead
            target = math.log(float(closes[target_index]) / float(closes[end]))
            if not math.isfinite(target):
                continue
            x_rows.append(vector)
            y_rows.append(target)
            baseline_rows.append(_baseline_return(vector, bars_ahead))
        if not x_rows:
            return _SupervisedData(
                x=np.empty((0, 7), dtype=float),
                y=np.empty((0,), dtype=float),
                baseline=np.empty((0,), dtype=float),
            )
        return _SupervisedData(x=np.vstack(x_rows), y=np.asarray(y_rows), baseline=np.asarray(baseline_rows))

    @staticmethod
    def _fit_challenger(x: np.ndarray, y: np.ndarray) -> HistGradientBoostingRegressor:
        model = HistGradientBoostingRegressor(
            learning_rate=0.05,
            max_iter=140,
            max_depth=3,
            min_samples_leaf=12,
            l2_regularization=1.0,
            random_state=42,
        )
        model.fit(x, y)
        return model

    @staticmethod
    def _persist_forecast(db: Session, forecast: ForecastResponse) -> None:
        existing = db.scalar(select(ForecastRecord).where(ForecastRecord.forecast_id == forecast.forecast_id))
        if existing is not None:
            return
        db.add(
            ForecastRecord(
                forecast_id=forecast.forecast_id,
                symbol=forecast.symbol,
                timeframe=forecast.timeframe,
                horizon=forecast.horizon,
                direction=forecast.direction,
                anchor_price=forecast.anchor_price,
                point_estimate=forecast.point_estimate,
                lower_bound=forecast.lower_bound,
                upper_bound=forecast.upper_bound,
                confidence_score=forecast.confidence_score,
                probability_up=forecast.probability_up,
                data_quality=forecast.data_quality,
                signal=forecast.signal,
                signal_quality=forecast.signal_quality,
                trade_allowed=forecast.trade_allowed,
                decision_reasons=forecast.decision_reasons,
                reasons=forecast.reasons,
                model_breakdown=forecast.model_breakdown,
                model_version=forecast.model_version,
                feature_version=forecast.feature_version,
                evidence_fingerprint=forecast.evidence_fingerprint,
                calibration_status=forecast.calibration_status,
                generated_at=_utc(forecast.generated_at),
                target_at=_utc(forecast.target_at),
                input_key=_input_key(forecast),
                evidence_manifest=forecast.evidence,
            )
        )
        db.commit()


def _signal_decision(
    *,
    direction: str,
    confidence: int,
    data_quality: int,
    calibration_status: str,
    validation_directional_accuracy: float | str | int | None = None,
) -> tuple[str, str, bool, list[str]]:
    """Fail closed: a forecast is not automatically a tradable signal."""
    reasons: list[str] = []
    if direction == "neutral":
        reasons.append("Expected movement is below the neutral threshold.")
    if calibration_status not in {"validation-based", "calibrated"}:
        reasons.append("Confidence is not independently calibrated yet.")
    if data_quality < 70:
        reasons.append("Input history does not meet the minimum data-quality threshold.")
    if confidence < 65:
        reasons.append("Directional confidence is below the minimum signal threshold.")
    if calibration_status == "validation-based":
        try:
            validation_accuracy = float(str(validation_directional_accuracy))
        except (TypeError, ValueError):
            validation_accuracy = 0.0
        if validation_accuracy < 55.0:
            reasons.append("Validation directional accuracy is below the 55% Paper Trading threshold.")
    if reasons:
        return "no_trade", "unverified" if calibration_status == "provisional" else "low", False, reasons
    quality = "high" if confidence >= 80 and data_quality >= 85 else "medium"
    signal = "buy" if direction == "upward" else "sell"
    if calibration_status == "validation-based":
        return (
            signal,
            "paper_only",
            False,
            ["Signal passed chronological validation and is eligible for Paper Trading only."],
        )
    return (
        signal,
        quality,
        True,
        ["Signal passed calibration, quality and confidence gates."],
    )


def _baseline_return(features: np.ndarray, bars_ahead: int) -> float:
    drift, volatility, ema_spread, rsi_scaled, momentum_3, momentum_6, momentum_12 = features
    rsi_centered = (rsi_scaled - 0.5) * 2.0
    projected = (
        drift * bars_ahead * 0.55
        + ema_spread * 0.28
        + momentum_3 * 0.07
        + momentum_6 * 0.08
        + momentum_12 * 0.07
        - rsi_centered * max(volatility, 0.0005) * 0.12
    )
    cap = min(0.30, max(0.015, max(volatility, 0.0005) * math.sqrt(max(1, bars_ahead)) * 4.0))
    return float(np.clip(projected, -cap, cap))


def _challenger_weight(baseline_mae: float, challenger_mae: float) -> float:
    if not math.isfinite(challenger_mae) or challenger_mae <= 0:
        return 0.0
    if not math.isfinite(baseline_mae) or baseline_mae <= 0:
        return 0.5
    ratio = baseline_mae / challenger_mae
    # Challenger receives material weight only when it actually beats baseline.
    if ratio <= 1.0:
        return 0.20
    return float(min(0.75, 0.35 + (ratio - 1.0) * 0.35))


def _bars_for_horizon(rows: Sequence[MarketCandleRecord], horizon: timedelta) -> int:
    if len(rows) < 2:
        return 0
    tail = list(rows[-50:])
    gaps = sorted(
        max(1.0, (_utc(right.opened_at) - _utc(left.opened_at)).total_seconds())
        for left, right in zip(tail, tail[1:])
    )
    median_gap = gaps[len(gaps) // 2] if gaps else 0
    if median_gap <= 0:
        return 0
    return max(1, int(round(horizon.total_seconds() / median_gap)))


def _fingerprint(rows: Sequence[MarketCandleRecord], horizon: str, timeframe: str, bars: int) -> str:
    digest = hashlib.sha256()
    digest.update(f"{MODEL_VERSION}|{FEATURE_VERSION}|{horizon}|{timeframe}|{bars}".encode())
    for row in rows:
        digest.update(
            f"|{_utc(row.opened_at).isoformat()}:{row.open}:{row.high}:{row.low}:{row.close}:{row.volume}:"
            f"{row.provider}:{row.currency}:{row.unit}:{row.market}:{row.content_fingerprint}".encode()
        )
    return digest.hexdigest()


def _input_key(forecast: ForecastResponse) -> str:
    return "|".join(
        [forecast.symbol, forecast.timeframe, forecast.horizon, forecast.model_version, forecast.evidence_fingerprint]
    )


def _evidence_manifest(rows: Sequence[MarketCandleRecord], *, model_version: str) -> dict[str, object]:
    if not rows:
        return {"model_version": model_version, "candle_ids": [], "providers": []}
    return {
        "model_version": model_version,
        "candle_ids": [row.id for row in rows],
        "providers": sorted({row.provider for row in rows}),
        "currencies": sorted({row.currency for row in rows}),
        "units": sorted({row.unit for row in rows}),
        "data_timestamps": [_utc(row.provider_timestamp or row.opened_at).isoformat() for row in rows],
        "generated_from": _utc(rows[0].opened_at).isoformat(),
        "generated_to": _utc(rows[-1].closed_at).isoformat(),
    }


def _forecast_schema(row: ForecastRecord) -> ForecastResponse:
    return ForecastResponse(
        forecast_id=row.forecast_id, symbol=row.symbol, timeframe=row.timeframe, horizon=row.horizon,
        direction=row.direction, anchor_price=row.anchor_price, point_estimate=row.point_estimate,
        lower_bound=row.lower_bound, upper_bound=row.upper_bound, confidence_score=row.confidence_score,
        probability_up=row.probability_up, data_quality=row.data_quality, signal=row.signal,
        signal_quality=row.signal_quality, trade_allowed=row.trade_allowed,
        decision_reasons=list(row.decision_reasons or []), model_version=row.model_version,
        feature_version=row.feature_version, evidence_fingerprint=row.evidence_fingerprint,
        calibration_status=row.calibration_status, generated_at=_utc(row.generated_at), target_at=_utc(row.target_at),
        reasons=list(row.reasons or []), model_breakdown=dict(row.model_breakdown or {}),
        evidence=dict(row.evidence_manifest or {}),
    )


def _utc(value: datetime) -> datetime:
    if value.tzinfo is None:
        return value.replace(tzinfo=timezone.utc)
    return value.astimezone(timezone.utc)
