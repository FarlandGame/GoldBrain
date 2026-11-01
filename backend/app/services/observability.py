from __future__ import annotations

from datetime import datetime, timedelta, timezone

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models.observability import MarketProviderMetricRecord
from app.models.market import MarketQuoteRecord
from app.models.candle import MarketCandleRecord
from app.core.market_quality import classify_freshness, excluded_domestic_reference_providers
from app.services.history import MarketHistoryService


def _utc(value: datetime) -> datetime:
    return value.replace(tzinfo=timezone.utc) if value.tzinfo is None else value.astimezone(timezone.utc)


class MarketObservabilityService:
    """Persist and aggregate provider health without retaining sensitive data."""

    def record(
        self,
        db: Session,
        *,
        provider: str,
        operation: str,
        status: str,
        latency_ms: int | None = None,
        error_kind: str | None = None,
        fallback_used: bool = False,
    ) -> None:
        db.add(
            MarketProviderMetricRecord(
                provider=provider.strip().lower()[:40],
                operation=operation.strip().lower()[:32],
                status=status.strip().lower()[:16],
                latency_ms=latency_ms,
                error_kind=(error_kind or None),
                fallback_used=bool(fallback_used),
            )
        )
        db.commit()

    def summary(self, db: Session, *, window_minutes: int = 60) -> list[dict[str, object]]:
        since = datetime.now(timezone.utc) - timedelta(minutes=max(1, min(window_minutes, 24 * 60)))
        rows = list(
            db.scalars(
                select(MarketProviderMetricRecord)
                .where(MarketProviderMetricRecord.observed_at >= since)
                .order_by(MarketProviderMetricRecord.observed_at.desc())
                .limit(5000)
            )
        )
        grouped: dict[tuple[str, str], list[MarketProviderMetricRecord]] = {}
        for row in rows:
            grouped.setdefault((row.provider, row.operation), []).append(row)
        result: list[dict[str, object]] = []
        for (provider, operation), items in sorted(grouped.items()):
            successes = sum(item.status == "success" for item in items)
            errors = len(items) - successes
            latencies = [item.latency_ms for item in items if item.latency_ms is not None]
            result.append(
                {
                    "provider": provider,
                    "operation": operation,
                    "request_count": len(items),
                    "success_count": successes,
                    "error_count": errors,
                    "success_rate": successes / len(items) if items else 0.0,
                    "error_rate": errors / len(items) if items else 0.0,
                    "average_latency_ms": sum(latencies) / len(latencies) if latencies else None,
                    "last_successful_update": next((_utc(item.observed_at) for item in items if item.status == "success"), None),
                    "fallback_count": sum(item.fallback_used for item in items),
                }
            )
        return result

    def market_snapshot(self, db: Session) -> dict[str, object]:
        now = datetime.now(timezone.utc)
        metrics = list(
            db.scalars(
                select(MarketProviderMetricRecord)
                .where(MarketProviderMetricRecord.observed_at >= now - timedelta(hours=24))
                .order_by(MarketProviderMetricRecord.observed_at.desc())
                .limit(5000)
            )
        )
        quotes = list(db.scalars(select(MarketQuoteRecord).order_by(MarketQuoteRecord.observed_at.desc()).limit(500)))
        latest: dict[str, MarketQuoteRecord] = {}
        for quote in quotes:
            if quote.provider.strip().lower() in excluded_domestic_reference_providers(quote.symbol):
                continue
            latest.setdefault(quote.symbol, quote)
        ages = {
            symbol: max(0, int((now - _utc(row.received_at or row.observed_at)).total_seconds()))
            for symbol, row in latest.items()
        }
        stale = sum(classify_freshness(row.received_at or row.observed_at, now=now).value in {"STALE", "DELAYED", "UNAVAILABLE"} for row in latest.values())
        candles = MarketHistoryService.trusted_candles(
            db, list(db.scalars(select(MarketCandleRecord).order_by(MarketCandleRecord.opened_at.desc()).limit(5000)))
        )
        gaps = 0
        by_series: dict[tuple[str, str, str], list[MarketCandleRecord]] = {}
        for row in candles:
            by_series.setdefault((row.symbol, row.timeframe, row.provider), []).append(row)
        deltas = {"1m": 60, "5m": 300, "15m": 900, "1h": 3600, "4h": 14400, "1d": 86400}
        for (_, timeframe, _), items in by_series.items():
            delta = deltas.get(timeframe)
            if not delta:
                continue
            ordered = sorted(items, key=lambda item: _utc(item.opened_at))
            gaps += sum((_utc(ordered[i + 1].opened_at) - _utc(ordered[i].opened_at)).total_seconds() > delta for i in range(len(ordered) - 1))
        return {
            "market_age_seconds": ages,
            "last_successful_update": {symbol: _utc(row.received_at or row.observed_at) for symbol, row in latest.items()},
            # Count fallback requests from telemetry rather than relying only
            # on quote rows, because a fallback provider may return a quote
            # without a predecessor timestamp in its payload.
            "fallback_usage": sum(bool(row.fallback_used) for row in metrics),
            "gap_count": gaps,
            "stale_data_count": stale,
        }
