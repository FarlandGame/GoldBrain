from datetime import datetime, timedelta, timezone
from typing import Annotated
from collections import Counter

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.api.dependencies import get_market_service
from app.core.security import require_client_access, require_private_access
from app.db.session import get_db
from app.schemas.history import (
    CandleBatchIn,
    CandleBatchResult,
    CandleHistoryResponse,
    MarketPriceSample,
    PriceSampleHistoryResponse,
    ProviderCandleFetchResult,
)
from app.core.market_quality import classify_freshness
from app.models.market import MarketQuoteRecord
from app.services.history import MarketHistoryService
from app.services.market_data import MarketDataError, MarketDataService
from app.services.market_data import SUPPORTED_SYMBOLS
from app.services.coingecko import COINGECKO_IDS

router = APIRouter(
    prefix="/history",
    tags=["history"],
    dependencies=[Depends(require_client_access)],
)
market_router = APIRouter(
    prefix="/market",
    tags=["market"],
    dependencies=[Depends(require_client_access)],
)
service = MarketHistoryService()


@market_router.get("/{asset}/samples", response_model=PriceSampleHistoryResponse)
async def asset_price_samples(
    asset: str,
    range: str = "24h",
    db: Session = Depends(get_db),
    market_data: MarketDataService = Depends(get_market_service),
) -> PriceSampleHistoryResponse:
    """Chart actual timestamped observations; never represent them as OHLC."""
    symbol = asset.strip().upper()
    if symbol not in {"USD", "EUR", "GOLD18"}:
        raise HTTPException(status_code=404, detail="Intraday samples are unavailable for this asset")
    if range != "24h":
        raise HTTPException(status_code=422, detail="Only the 24h sample range is supported")
    now = datetime.now(timezone.utc)
    start = now - timedelta(hours=24)
    if symbol == "EUR":
        # Navasan's /dailyCurrency endpoint rejects all documented EUR-like
        # item names. Use only source-timestamped EUR /latest observations that
        # the quote collector has already persisted, and show insufficient
        # history until there are two distinct observations.
        rows = db.scalars(select(MarketQuoteRecord).where(
            MarketQuoteRecord.symbol == symbol,
            MarketQuoteRecord.provider == "navasan",
            MarketQuoteRecord.provider_timestamp.is_not(None),
            MarketQuoteRecord.provider_timestamp >= start,
            MarketQuoteRecord.provider_timestamp <= now + timedelta(seconds=30),
            MarketQuoteRecord.currency == "IRT",
            MarketQuoteRecord.unit == "currency_unit",
            MarketQuoteRecord.data_quality_status.in_(("VALID", "UNVERIFIED")),
        ).order_by(MarketQuoteRecord.provider_timestamp.asc())).all()
        by_time: dict[datetime, MarketPriceSample] = {}
        for row in rows:
            if row.provider_timestamp is None or row.price <= 0:
                continue
            flags = set(row.quality_flags or [])
            if row.data_quality_status == "UNVERIFIED":
                # Older Navasan observations were marked only because their
                # Toman unit had not yet been corroborated with Navasan's own
                # widget. Do not rehabilitate other unverified evidence.
                if "unit_from_provider_catalog" not in flags or flags - {
                    "unit_from_provider_catalog", "provider_unverified",
                }:
                    continue
                flags.difference_update({"unit_from_provider_catalog", "provider_unverified"})
            observed = row.provider_timestamp.replace(tzinfo=timezone.utc) if row.provider_timestamp.tzinfo is None else row.provider_timestamp.astimezone(timezone.utc)
            received = row.received_at or row.created_at
            received = received.replace(tzinfo=timezone.utc) if received.tzinfo is None else received.astimezone(timezone.utc)
            previous = by_time.get(observed)
            if previous is not None and previous.price != row.price:
                continue
            by_time[observed] = MarketPriceSample(
                symbol=symbol, price=row.price, currency=row.currency,
                unit=row.unit, market=row.market, provider="navasan",
                upstream_source=row.upstream_source or "eur",
                provider_timestamp=observed, received_at=received,
                freshness_status=classify_freshness(observed, now=now).value,
                data_quality_status="VALID",
                quality_flags=[*sorted(flags), "price_sample_not_ohlc"],
            )
        samples = [by_time[observed] for observed in sorted(by_time)]
    else:
        try:
            samples = await market_data.fetch_navasan_intraday_samples(
                symbol=symbol, start_at=start, end_at=now,
            )
        except MarketDataError as exc:
            raise HTTPException(status_code=503, detail=str(exc)) from exc
    return PriceSampleHistoryResponse(symbol=symbol, range=range, samples=samples)


@router.post("/candles", response_model=CandleBatchResult, dependencies=[Depends(require_private_access)])
def ingest_candles(payload: CandleBatchIn, db: Session = Depends(get_db)) -> CandleBatchResult:
    if len(payload.candles) > 5000:
        raise HTTPException(status_code=413, detail="Maximum 5000 candles per request.")
    result = service.upsert_candles(db, payload.candles)
    return CandleBatchResult(inserted=result.inserted, updated=result.updated, rejected=result.rejected)


@router.get("/candles", response_model=CandleHistoryResponse)
def candles(
    symbol: str,
    timeframe: str = "1h",
    limit: Annotated[int, Query(ge=2, le=5000)] = 500,
    provider: str | None = None,
    before: datetime | None = None,
    currency: str | None = None,
    unit: str | None = None,
    market: str | None = None,
    db: Session = Depends(get_db),
) -> CandleHistoryResponse:
    rows = service.get_candles(
        db, symbol, timeframe, limit=limit, provider=provider, before=before,
        currency=currency, unit=unit, market=market,
    )
    return CandleHistoryResponse(
        symbol=symbol.strip().upper(),
        timeframe=timeframe.strip().lower(),
        candles=[service.to_schema(row) for row in rows],
    )


@router.post(
    "/aggregate-quotes",
    response_model=CandleBatchResult,
    dependencies=[Depends(require_private_access)],
)
def aggregate_quotes(
    symbol: str,
    timeframe: str = "5m",
    lookback_hours: Annotated[int, Query(ge=1, le=2160)] = 72,
    db: Session = Depends(get_db),
) -> CandleBatchResult:
    result = service.build_quote_candles(
        db,
        symbol=symbol,
        timeframe=timeframe,
        lookback_hours=lookback_hours,
    )
    return CandleBatchResult(inserted=result.inserted, updated=result.updated, rejected=result.rejected)


@router.post(
    "/fetch-wallex",
    response_model=ProviderCandleFetchResult,
    dependencies=[Depends(require_private_access)],
)
async def fetch_wallex_candles(
    symbol: str,
    timeframe: str = "1h",
    lookback_hours: Annotated[int, Query(ge=1, le=2160)] = 720,
    db: Session = Depends(get_db),
    market_data: MarketDataService = Depends(get_market_service),
) -> ProviderCandleFetchResult:
    end_at = datetime.now(timezone.utc)
    try:
        candles = await market_data.fetch_wallex_candles(
            symbol=symbol,
            timeframe=timeframe,
            start_at=end_at - timedelta(hours=lookback_hours),
            end_at=end_at,
        )
    except MarketDataError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc
    result = service.upsert_candles(db, candles)
    return ProviderCandleFetchResult(
        symbol=symbol.strip().upper(),
        timeframe=timeframe.strip().lower(),
        provider="wallex",
        inserted=result.inserted,
        updated=result.updated,
        rejected=result.rejected,
    )


@router.post(
    "/fetch-navasan",
    response_model=ProviderCandleFetchResult,
    dependencies=[Depends(require_private_access)],
)
async def fetch_navasan_daily_candles(
    symbol: str,
    lookback_days: Annotated[int, Query(ge=2, le=35)] = 35,
    db: Session = Depends(get_db),
    market_data: MarketDataService = Depends(get_market_service),
) -> ProviderCandleFetchResult:
    """Backfill documented domestic daily OHLC without filling missing days."""
    end_at = datetime.now(timezone.utc)
    try:
        candles = await market_data.fetch_navasan_daily_candles(
            symbol=symbol, start_at=end_at - timedelta(days=lookback_days), end_at=end_at,
        )
    except MarketDataError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc
    result = service.upsert_candles(db, candles)
    return ProviderCandleFetchResult(
        symbol=symbol.strip().upper(), timeframe="1d", provider="navasan",
        inserted=result.inserted, updated=result.updated, rejected=result.rejected,
    )

@market_router.get("/{asset}/candles", response_model=CandleHistoryResponse)
async def asset_candles(
    asset: str,
    timeframe: str = "1h",
    limit: Annotated[int, Query(ge=2, le=5000)] = 500,
    provider: str | None = None,
    currency: str | None = None,
    before: datetime | None = None,
    db: Session = Depends(get_db),
    market_data: MarketDataService = Depends(get_market_service),
) -> CandleHistoryResponse:
    symbol = asset.strip().upper()
    if symbol not in SUPPORTED_SYMBOLS:
        raise HTTPException(status_code=404, detail="Unsupported market asset")
    normalized_timeframe = timeframe.strip().lower()
    if before is None and normalized_timeframe in {"1m", "1h", "1d"} and provider != "quote-collector":
        now = datetime.now(timezone.utc)
        lookback = (
            timedelta(hours=1) if normalized_timeframe == "1m"
            else timedelta(days=35) if normalized_timeframe == "1d"
            else timedelta(days=30) if limit >= 700
            else timedelta(days=7)
        )
        delta = (
            timedelta(minutes=1) if normalized_timeframe == "1m"
            else timedelta(days=1) if normalized_timeframe == "1d"
            else timedelta(hours=1)
        )
        existing = service.get_candles(db, symbol, normalized_timeframe, limit=5000)
        groups: dict[tuple[str, str, str, str], list[datetime]] = {}
        requested_provider = (provider or "").strip().lower()
        for row in existing:
            if requested_provider and row.provider != requested_provider:
                continue
            key = (row.provider, row.currency, row.unit, row.market)
            opened = row.opened_at
            groups.setdefault(key, []).append(
                opened.replace(tzinfo=timezone.utc)
                if opened.tzinfo is None else opened.astimezone(timezone.utc)
            )
        covered = any(
            len(times) >= 2
            and min(times) <= now - lookback + delta * 2
            and max(times) >= now - delta * 3
            for times in groups.values()
        )
        if not covered:
            upstream: list = []
            start_at = now - lookback
            wallex_symbols: frozenset[str] = getattr(market_data, "wallex_candle_symbols", frozenset())
            if symbol in wallex_symbols and requested_provider in {"", "wallex"}:
                try:
                    upstream = await market_data.fetch_wallex_candles(
                        symbol=symbol, timeframe=normalized_timeframe,
                        start_at=start_at, end_at=now,
                    )
                except MarketDataError:
                    pass
            navasan_symbols: frozenset[str] = getattr(market_data, "navasan_candle_symbols", frozenset())
            if not upstream and normalized_timeframe == "1d" and symbol in navasan_symbols and requested_provider in {"", "navasan"}:
                try:
                    upstream = await market_data.fetch_navasan_daily_candles(
                        symbol=symbol, start_at=start_at, end_at=now,
                    )
                except MarketDataError:
                    pass
            if not upstream and hasattr(market_data, "fetch_coingecko_samples") and symbol in COINGECKO_IDS and symbol != "USDT" and requested_provider in {"", "coingecko"}:
                try:
                    upstream = await market_data.fetch_coingecko_samples(
                        symbol=symbol, timeframe=normalized_timeframe,
                        start_at=start_at, end_at=now,
                    )
                except MarketDataError:
                    pass
            if upstream:
                service.upsert_candles(db, upstream)
    rows = service.get_candles(
        db, symbol, normalized_timeframe, limit=5000, provider=provider,
        currency=currency, before=before,
    )
    # A chart must never join USD and USDT candles (or two market sources)
    # into one continuous line. Prefer the most complete homogeneous series.
    if provider is None or currency is None:
        counts = Counter((row.provider, row.currency, row.unit, row.market) for row in rows)
        if counts:
            chosen = max(counts, key=lambda key: counts[key])
            rows = [row for row in rows if (row.provider, row.currency, row.unit, row.market) == chosen]
    rows = rows[-limit:]
    return CandleHistoryResponse(
        symbol=symbol,
        timeframe=normalized_timeframe,
        candles=[service.to_schema(row) for row in rows],
    )
