from __future__ import annotations

import hashlib
import math
from collections import Counter
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from typing import Iterable

from sqlalchemy import Select, select
from sqlalchemy.orm import Session

from app.core.market_quality import DataQualityStatus, FreshnessStatus, allowed_currencies, classify_freshness, excluded_domestic_reference_providers, expected_metadata, validate_price
from app.models.candle import MarketCandleRecord
from app.models.market import MarketQuoteRecord
from app.schemas.history import MarketCandle
from app.schemas.market import MarketQuote
from app.services.market_data import SUPPORTED_SYMBOLS

ALLOWED_TIMEFRAMES = frozenset({"1m", "5m", "15m", "1h", "4h", "1d"})


@dataclass(frozen=True)
class UpsertResult:
    inserted: int = 0
    updated: int = 0
    rejected: int = 0


class MarketHistoryService:
    """Append-only persistence boundary for raw observations and candles."""

    def latest_quote(self, db: Session, symbol: str) -> MarketQuote | None:
        """Return the persisted last-known observation with an explicit stale flag."""
        normalized = symbol.strip().upper()
        query = select(MarketQuoteRecord).where(MarketQuoteRecord.symbol == normalized)
        excluded = excluded_domestic_reference_providers(normalized)
        if excluded:
            query = query.where(MarketQuoteRecord.provider.not_in(excluded))
        row = db.scalar(query.order_by(MarketQuoteRecord.observed_at.desc()).limit(1))
        if row is None:
            return None
        flags = list(row.quality_flags or [])
        if "cached_last_known" not in flags:
            flags.append("cached_last_known")
        return MarketQuote(
            asset=normalized, symbol=normalized, name=normalized,
            currency=row.currency, price=row.price, updated_at=_utc(row.observed_at),
            provider=row.provider, upstream_source=row.upstream_source,
            unit=row.unit, market=row.market,
            provider_timestamp=_utc(row.provider_timestamp) if row.provider_timestamp else None,
            received_at=_utc(row.received_at) if row.received_at else None,
            latency_ms=row.latency_ms, freshness_status=FreshnessStatus.STALE.value,
            freshness=FreshnessStatus.STALE.value,
            data_quality_status=row.data_quality_status,
            quality_flags=flags, fallback_from=row.fallback_from,
            provider_spread_percent=row.provider_spread_percent,
        )

    def persist_quotes(self, db: Session, quotes: Iterable[MarketQuote]) -> int:
        inserted = 0
        pending_fingerprints: set[str] = set()
        for quote in quotes:
            normalized = self._normalize_quote(quote)
            if normalized is None:
                continue
            fingerprint = _quote_fingerprint(normalized)
            if fingerprint in pending_fingerprints or db.scalar(select(MarketQuoteRecord.id).where(MarketQuoteRecord.content_fingerprint == fingerprint)):
                continue
            pending_fingerprints.add(fingerprint)
            db.add(
                MarketQuoteRecord(
                    symbol=normalized.symbol,
                    price=normalized.price,
                    currency=normalized.currency,
                    provider=normalized.provider,
                    upstream_source=normalized.upstream_source,
                    observed_at=_utc(normalized.updated_at),
                    unit=normalized.unit,
                    market=normalized.market,
                    provider_timestamp=normalized.provider_timestamp,
                    received_at=normalized.received_at or datetime.now(timezone.utc),
                    latency_ms=normalized.latency_ms,
                    freshness_status=normalized.freshness_status,
                    data_quality_status=normalized.data_quality_status,
                    quality_flags=list(normalized.quality_flags),
                    fallback_from=normalized.fallback_from,
                    provider_spread_percent=normalized.provider_spread_percent,
                    content_fingerprint=fingerprint,
                )
            )
            inserted += 1
        if inserted:
            db.commit()
        return inserted

    def upsert_candles(self, db: Session, candles: Iterable[MarketCandle]) -> UpsertResult:
        inserted = rejected = 0
        pending_fingerprints: set[str] = set()
        pending_keys: set[tuple[str, str, str, datetime]] = set()
        for candle in candles:
            normalized = self._validate(candle)
            if normalized is None:
                rejected += 1
                continue
            if normalized.provider == "quote-collector" and excluded_domestic_reference_providers(normalized.symbol):
                sources = self._quote_sources(db, normalized.source_tick_ids)
                if not self._collector_sources_match(normalized, sources):
                    rejected += 1
                    continue
            opened_at = _utc(normalized.opened_at)
            key = (normalized.symbol, normalized.timeframe, normalized.provider, opened_at)
            if key in pending_keys:
                rejected += 1
                continue
            existing = db.scalar(
                select(MarketCandleRecord).where(
                    MarketCandleRecord.symbol == normalized.symbol,
                    MarketCandleRecord.timeframe == normalized.timeframe,
                    MarketCandleRecord.provider == normalized.provider,
                    MarketCandleRecord.opened_at == opened_at,
                )
            )
            if existing is not None:
                rejected += 1
                continue
            fingerprint = _candle_fingerprint(normalized)
            if fingerprint in pending_fingerprints or db.scalar(select(MarketCandleRecord.id).where(MarketCandleRecord.content_fingerprint == fingerprint)):
                rejected += 1
                continue
            pending_keys.add(key)
            pending_fingerprints.add(fingerprint)
            db.add(
                MarketCandleRecord(
                    symbol=normalized.symbol,
                    timeframe=normalized.timeframe,
                    currency=normalized.currency,
                    provider=normalized.provider,
                    upstream_source=normalized.upstream_source,
                    opened_at=opened_at,
                    closed_at=_utc(normalized.closed_at),
                    open=normalized.open,
                    high=normalized.high,
                    low=normalized.low,
                    close=normalized.close,
                    volume=normalized.volume,
                    unit=normalized.unit,
                    market=normalized.market,
                    provider_timestamp=normalized.provider_timestamp,
                    received_at=normalized.received_at or datetime.now(timezone.utc),
                    latency_ms=normalized.latency_ms,
                    freshness_status=normalized.freshness_status,
                    data_quality_status=normalized.data_quality_status,
                    quality_flags=list(normalized.quality_flags),
                    source_tick_ids=list(normalized.source_tick_ids),
                    is_complete=normalized.is_complete,
                    content_fingerprint=fingerprint,
                )
            )
            inserted += 1
        if inserted:
            db.commit()
        return UpsertResult(inserted=inserted, rejected=rejected)

    def get_candles(
        self, db: Session, symbol: str, timeframe: str, *, limit: int = 500,
        provider: str | None = None, before: datetime | None = None,
        closed_before: datetime | None = None, currency: str | None = None,
        unit: str | None = None, market: str | None = None,
    ) -> list[MarketCandleRecord]:
        symbol = symbol.strip().upper()
        timeframe = timeframe.strip().lower()
        query: Select[tuple[MarketCandleRecord]] = select(MarketCandleRecord).where(
            MarketCandleRecord.symbol == symbol,
            MarketCandleRecord.timeframe == timeframe,
            MarketCandleRecord.is_complete.is_(True),
        )
        excluded = excluded_domestic_reference_providers(symbol)
        if excluded:
            query = query.where(MarketCandleRecord.provider.not_in(excluded))
        if provider:
            query = query.where(MarketCandleRecord.provider == provider.strip().lower())
        if currency:
            query = query.where(MarketCandleRecord.currency == currency.strip().upper())
        if unit:
            query = query.where(MarketCandleRecord.unit == unit.strip().lower())
        if market:
            query = query.where(MarketCandleRecord.market == market.strip().upper())
        if before is not None:
            query = query.where(MarketCandleRecord.opened_at <= _utc(before))
        cutoff = _utc(closed_before or datetime.now(timezone.utc))
        query = query.where(MarketCandleRecord.closed_at <= cutoff)
        query = query.order_by(MarketCandleRecord.opened_at.desc()).limit(max(2, min(limit, 5000)))
        rows = self.trusted_candles(db, list(db.scalars(query)))
        rows.reverse()
        return rows

    @classmethod
    def trusted_candles(cls, db: Session, rows: list[MarketCandleRecord]) -> list[MarketCandleRecord]:
        """Hide old domestic reference candles, including aggregates with tainted ticks."""
        collector_ids = {
            tick_id for row in rows
            if row.provider == "quote-collector" and excluded_domestic_reference_providers(row.symbol)
            for tick_id in (row.source_tick_ids or [])
        }
        sources = cls._quote_sources(db, collector_ids)
        return [
            row for row in rows
            if row.provider.strip().lower() not in excluded_domestic_reference_providers(row.symbol)
            and (
                row.provider != "quote-collector"
                or not excluded_domestic_reference_providers(row.symbol)
                or cls._collector_sources_match(row, sources)
            )
        ]

    @staticmethod
    def _quote_sources(db: Session, source_tick_ids: Iterable[int]) -> dict[int, MarketQuoteRecord]:
        ids = list(set(source_tick_ids))
        if not ids:
            return {}
        sources: dict[int, MarketQuoteRecord] = {}
        for start in range(0, len(ids), 900):
            batch = ids[start:start + 900]
            sources.update({
                row.id: row for row in db.scalars(select(MarketQuoteRecord).where(MarketQuoteRecord.id.in_(batch)))
            })
        return sources

    @staticmethod
    def _collector_sources_match(
        candle: MarketCandle | MarketCandleRecord, sources: dict[int, MarketQuoteRecord],
    ) -> bool:
        ids = candle.source_tick_ids or []
        if not ids:
            return False
        excluded = excluded_domestic_reference_providers(candle.symbol)
        return all(
            (source := sources.get(tick_id)) is not None
            and source.symbol == candle.symbol
            and source.provider.strip().lower() not in excluded
            and source.currency == candle.currency
            and source.unit == candle.unit
            and source.market == candle.market
            for tick_id in ids
        )

    def gap_count(self, rows: Iterable[MarketCandleRecord], timeframe: str) -> int:
        ordered = sorted(rows, key=lambda row: _utc(row.opened_at))
        delta = _timeframe_delta(timeframe)
        if delta is None or len(ordered) < 2:
            return 0
        return sum(1 for left, right in zip(ordered, ordered[1:]) if _utc(right.opened_at) - _utc(left.opened_at) > delta)

    def build_quote_candles(
        self, db: Session, *, symbol: str, timeframe: str = "5m", lookback_hours: int = 72,
        provider: str = "quote-collector", now: datetime | None = None,
    ) -> UpsertResult:
        symbol = symbol.strip().upper()
        timeframe = timeframe.strip().lower()
        delta = _timeframe_delta(timeframe)
        if delta is None:
            return UpsertResult(rejected=1)
        cutoff = _utc(now or datetime.now(timezone.utc))
        since = cutoff - timedelta(hours=max(1, min(lookback_hours, 24 * 90)))
        quote_query = select(MarketQuoteRecord).where(
            MarketQuoteRecord.symbol == symbol, MarketQuoteRecord.observed_at >= since
        )
        excluded = excluded_domestic_reference_providers(symbol)
        if excluded:
            quote_query = quote_query.where(MarketQuoteRecord.provider.not_in(excluded))
        quotes = list(db.scalars(quote_query.order_by(MarketQuoteRecord.observed_at.asc())))
        if not quotes:
            return UpsertResult()
        series = Counter((q.provider, q.currency, q.unit, q.market) for q in quotes).most_common(1)[0][0]
        quotes = [q for q in quotes if (q.provider, q.currency, q.unit, q.market) == series]
        buckets: dict[datetime, list[MarketQuoteRecord]] = {}
        seconds = int(delta.total_seconds())
        for quote in quotes:
            opened = datetime.fromtimestamp((int(_utc(quote.observed_at).timestamp()) // seconds) * seconds, tz=timezone.utc)
            buckets.setdefault(opened, []).append(quote)
        candles: list[MarketCandle] = []
        for opened, items in sorted(buckets.items()):
            if opened + delta > cutoff:
                continue
            prices = [item.price for item in items if validate_price(item.price) is not None]
            if not prices:
                continue
            first = items[0]
            freshness = classify_freshness(first.observed_at, now=cutoff)
            flags = list(first.quality_flags or [])
            if freshness in {FreshnessStatus.STALE, FreshnessStatus.UNAVAILABLE}:
                flags.append("stale_source")
            candles.append(MarketCandle(
                symbol=symbol, timeframe=timeframe, currency=first.currency, provider=provider,
                upstream_source="persisted-live-quotes", opened_at=opened, closed_at=opened + delta,
                open=prices[0], high=max(prices), low=min(prices), close=prices[-1], volume=None,
                unit=first.unit, market=first.market, provider_timestamp=first.provider_timestamp,
                received_at=first.received_at, latency_ms=first.latency_ms,
                freshness_status=freshness.value, data_quality_status=first.data_quality_status,
                quality_flags=flags, source_tick_ids=[item.id for item in items], is_complete=True,
            ))
        return self.upsert_candles(db, candles)

    @staticmethod
    def to_schema(row: MarketCandleRecord) -> MarketCandle:
        return MarketCandle(
            symbol=row.symbol, timeframe=row.timeframe, currency=row.currency, provider=row.provider,
            upstream_source=row.upstream_source, opened_at=_utc(row.opened_at), closed_at=_utc(row.closed_at),
            open=row.open, high=row.high, low=row.low, close=row.close, volume=row.volume,
            unit=row.unit, market=row.market,
            provider_timestamp=_utc(row.provider_timestamp) if row.provider_timestamp else None,
            received_at=_utc(row.received_at) if row.received_at else None, latency_ms=row.latency_ms,
            freshness_status=row.freshness_status, data_quality_status=row.data_quality_status,
            quality_flags=list(row.quality_flags or []), source_tick_ids=list(row.source_tick_ids or []),
            is_complete=row.is_complete,
        )

    @staticmethod
    def _normalize_quote(quote: MarketQuote) -> MarketQuote | None:
        symbol = quote.symbol.strip().upper()
        price = validate_price(quote.price)
        metadata = expected_metadata(symbol)
        if symbol not in SUPPORTED_SYMBOLS or price is None or not quote.provider.strip():
            return None
        if quote.provider.strip().lower() in excluded_domestic_reference_providers(symbol):
            return None
        expected_unit, expected_currency, expected_market = metadata or ("unknown", quote.currency, "unknown")
        currency = quote.currency.strip().upper()
        if currency not in (allowed_currencies(symbol) or frozenset({expected_currency})):
            return None
        if quote.unit not in {"", "unknown", expected_unit} or quote.market not in {"", "unknown", expected_market}:
            return None
        updated = _utc(quote.updated_at)
        provider_updated = _utc(quote.provider_timestamp) if quote.provider_timestamp else None
        now = datetime.now(timezone.utc)
        if updated > now + timedelta(seconds=30) or (
            provider_updated is not None and provider_updated > now + timedelta(seconds=30)
        ):
            return None
        freshness_at = provider_updated or updated
        return quote.model_copy(update={
            "symbol": symbol, "price": price, "currency": currency, "updated_at": updated,
            "unit": expected_unit,
            "market": expected_market,
            "provider_timestamp": quote.provider_timestamp
            if quote.provider_timestamp is not None
            else (None if "provider_timestamp_unavailable" in quote.quality_flags else updated),
            "received_at": quote.received_at or datetime.now(timezone.utc),
            "freshness_status": quote.freshness_status
            if quote.freshness_status in {
                FreshnessStatus.DELAYED.value,
                FreshnessStatus.STALE.value,
                FreshnessStatus.UNAVAILABLE.value,
            }
            else classify_freshness(freshness_at).value,
            "data_quality_status": quote.data_quality_status or DataQualityStatus.VALID.value,
        })

    def _validate(self, candle: MarketCandle) -> MarketCandle | None:
        symbol = candle.symbol.strip().upper()
        timeframe = candle.timeframe.strip().lower()
        provider = candle.provider.strip().lower()
        currency = candle.currency.strip().upper()
        values = (candle.open, candle.high, candle.low, candle.close)
        metadata = expected_metadata(symbol)
        expected_unit, expected_currency, expected_market = metadata or ("unknown", currency, "unknown")
        if (symbol not in SUPPORTED_SYMBOLS or timeframe not in ALLOWED_TIMEFRAMES or not provider or not currency
            or provider in excluded_domestic_reference_providers(symbol)
            or any(validate_price(value) is None for value in values)
            or candle.high < max(candle.open, candle.close, candle.low)
            or candle.low > min(candle.open, candle.close, candle.high)
            or _utc(candle.closed_at) <= _utc(candle.opened_at)
            or _utc(candle.opened_at) > datetime.now(timezone.utc) + timedelta(seconds=30)
            or (candle.volume is not None and (not math.isfinite(candle.volume) or candle.volume < 0))
            or currency not in (allowed_currencies(symbol) or frozenset({expected_currency}))
            or candle.unit not in {"", "unknown", expected_unit}
            or candle.market not in {"", "unknown", expected_market}):
            return None
        return candle.model_copy(update={
            "symbol": symbol, "timeframe": timeframe, "provider": provider, "currency": currency,
            "unit": expected_unit,
            "market": expected_market,
            "opened_at": _utc(candle.opened_at), "closed_at": _utc(candle.closed_at),
            "provider_timestamp": candle.provider_timestamp or _utc(candle.opened_at),
            "received_at": candle.received_at or datetime.now(timezone.utc),
            "freshness_status": candle.freshness_status or FreshnessStatus.FRESH.value,
            "data_quality_status": candle.data_quality_status or DataQualityStatus.VALID.value,
        })


def _quote_fingerprint(quote: MarketQuote) -> str:
    return hashlib.sha256("|".join([quote.symbol, quote.provider.lower(), quote.currency, quote.unit, _utc(quote.updated_at).isoformat(), str(quote.price)]).encode()).hexdigest()


def _candle_fingerprint(candle: MarketCandle) -> str:
    return hashlib.sha256("|".join([candle.symbol, candle.timeframe, candle.provider.lower(), candle.currency, candle.unit, _utc(candle.opened_at).isoformat(), str(candle.open), str(candle.high), str(candle.low), str(candle.close), str(candle.volume)]).encode()).hexdigest()


def _utc(value: datetime) -> datetime:
    return value.replace(tzinfo=timezone.utc) if value.tzinfo is None else value.astimezone(timezone.utc)


def _timeframe_delta(timeframe: str) -> timedelta | None:
    return {"1m": timedelta(minutes=1), "5m": timedelta(minutes=5), "15m": timedelta(minutes=15), "1h": timedelta(hours=1), "4h": timedelta(hours=4), "1d": timedelta(days=1)}.get(timeframe)
