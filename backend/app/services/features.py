from __future__ import annotations

from dataclasses import dataclass
from statistics import median

import numpy as np

from app.models.candle import MarketCandleRecord


FEATURE_VERSION = "price-features-v2"


@dataclass(frozen=True)
class FeatureSnapshot:
    values: dict[str, float]
    reasons: tuple[str, ...]
    data_quality: int


class FeatureEngine:
    """Leak-free price feature builder used by baseline and challenger models."""

    minimum_points = 24

    def snapshot(self, rows: list[MarketCandleRecord]) -> FeatureSnapshot:
        if len(rows) < self.minimum_points:
            raise ValueError(f"At least {self.minimum_points} candles are required")
        closes = np.asarray([row.close for row in rows], dtype=float)
        highs = np.asarray([row.high for row in rows], dtype=float)
        lows = np.asarray([row.low for row in rows], dtype=float)
        if not np.all(np.isfinite(closes)) or np.any(closes <= 0):
            raise ValueError("Invalid close series")
        log_returns = np.diff(np.log(closes))
        recent = log_returns[-min(48, len(log_returns)) :]
        ema_fast = _ema(closes, min(8, len(closes)))
        ema_slow = _ema(closes, min(21, len(closes)))
        rsi = _rsi(closes, min(14, len(closes) - 1))
        atr = _atr(highs, lows, closes, min(14, len(closes) - 1))
        volatility = float(np.std(recent, ddof=1)) if len(recent) > 1 else 0.0
        drift = float(np.median(recent)) if len(recent) else 0.0
        momentum_3 = _return_over(closes, 3)
        momentum_6 = _return_over(closes, 6)
        momentum_12 = _return_over(closes, 12)
        values = {
            "drift": drift,
            "volatility": max(0.0, volatility),
            "ema_spread": float((ema_fast / ema_slow) - 1) if ema_slow > 0 else 0.0,
            "rsi": rsi,
            "atr_percent": float(atr / closes[-1]) if closes[-1] > 0 else 0.0,
            "momentum_3": momentum_3,
            "momentum_6": momentum_6,
            "momentum_12": momentum_12,
            "last_close": float(closes[-1]),
        }
        reasons: list[str] = []
        if values["ema_spread"] > 0.002:
            reasons.append("Fast EMA is above the slow EMA.")
        elif values["ema_spread"] < -0.002:
            reasons.append("Fast EMA is below the slow EMA.")
        if rsi >= 70:
            reasons.append("RSI is in an overbought region.")
        elif rsi <= 30:
            reasons.append("RSI is in an oversold region.")
        if momentum_6 > 0.005:
            reasons.append("Recent six-bar momentum is positive.")
        elif momentum_6 < -0.005:
            reasons.append("Recent six-bar momentum is negative.")
        if volatility > 0.02:
            reasons.append("Recent volatility is elevated.")
        if not reasons:
            reasons.append("Signals are mixed; no single technical factor dominates.")
        quality = self._quality(rows)
        return FeatureSnapshot(values=values, reasons=tuple(reasons), data_quality=quality)

    def vector(self, closes: np.ndarray) -> np.ndarray:
        if len(closes) < self.minimum_points:
            raise ValueError("Insufficient points")
        returns = np.diff(np.log(closes))
        recent = returns[-min(48, len(returns)) :]
        ema_fast = _ema(closes, min(8, len(closes)))
        ema_slow = _ema(closes, min(21, len(closes)))
        return np.asarray(
            [
                float(np.median(recent)) if len(recent) else 0.0,
                float(np.std(recent, ddof=1)) if len(recent) > 1 else 0.0,
                (ema_fast / ema_slow - 1) if ema_slow > 0 else 0.0,
                _rsi(closes, min(14, len(closes) - 1)) / 100.0,
                _return_over(closes, 3),
                _return_over(closes, 6),
                _return_over(closes, 12),
            ],
            dtype=float,
        )

    def _quality(self, rows: list[MarketCandleRecord]) -> int:
        times = [row.opened_at for row in rows]
        gaps = []
        for left, right in zip(times, times[1:]):
            seconds = max(0.0, (right - left).total_seconds())
            if seconds:
                gaps.append(seconds)
        if not gaps:
            return 50
        med = median(gaps)
        irregular = sum(1 for gap in gaps if gap > med * 1.8)
        completeness = 1 - irregular / max(1, len(gaps))
        sample_score = min(1.0, len(rows) / 240.0)
        score = 55 + completeness * 25 + sample_score * 20
        return int(max(0, min(100, round(score))))


def _ema(values: np.ndarray, period: int) -> float:
    period = max(1, period)
    alpha = 2.0 / (period + 1.0)
    result = float(values[0])
    for value in values[1:]:
        result = alpha * float(value) + (1 - alpha) * result
    return result


def _rsi(values: np.ndarray, period: int) -> float:
    if period <= 0 or len(values) < 2:
        return 50.0
    deltas = np.diff(values)[-period:]
    gains = np.clip(deltas, 0, None)
    losses = np.clip(-deltas, 0, None)
    avg_gain = float(np.mean(gains)) if len(gains) else 0.0
    avg_loss = float(np.mean(losses)) if len(losses) else 0.0
    if avg_loss <= 1e-12:
        return 100.0 if avg_gain > 0 else 50.0
    rs = avg_gain / avg_loss
    return 100.0 - 100.0 / (1.0 + rs)


def _atr(highs: np.ndarray, lows: np.ndarray, closes: np.ndarray, period: int) -> float:
    if len(closes) < 2:
        return 0.0
    trs = []
    start = max(1, len(closes) - max(1, period))
    for index in range(start, len(closes)):
        trs.append(
            max(
                float(highs[index] - lows[index]),
                abs(float(highs[index] - closes[index - 1])),
                abs(float(lows[index] - closes[index - 1])),
            )
        )
    return float(np.mean(trs)) if trs else 0.0


def _return_over(values: np.ndarray, bars: int) -> float:
    if len(values) <= bars or values[-bars - 1] <= 0:
        return 0.0
    return float(values[-1] / values[-bars - 1] - 1.0)
