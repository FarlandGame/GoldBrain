from __future__ import annotations

import asyncio
import logging
import math
import time
from dataclasses import dataclass
from datetime import date, datetime, timedelta, timezone
from typing import Iterable, cast
from zoneinfo import ZoneInfo

import httpx

from app.core.config import Settings
from app.core.market_quality import (
    DataQualityStatus,
    FreshnessStatus,
    ADDITIONAL_WALLEX_ASSETS,
    TRACKED_CRYPTO_ASSETS,
    TRACKED_CRYPTO_TOP20,
    classify_freshness,
    expected_metadata,
    normalize_iranian_price,
)
from app.schemas.history import MarketCandle, MarketPriceSample
from app.schemas.market import AssetMetadata, MarketQuote
from app.services.coingecko import COINGECKO_IDS, CoinGeckoError, CoinGeckoProvider

SUPPORTED_ASSETS: tuple[AssetMetadata, ...] = (
    AssetMetadata(
        symbol="USD",
        name="US Dollar / Toman",
        asset_class="fx",
        quote_currency="IRT",
        live_quote=True,
        forecast=True,
    ),
    AssetMetadata(
        symbol="EUR",
        name="Euro / Toman",
        asset_class="fx",
        quote_currency="IRT",
        live_quote=True,
        forecast=False,
    ),
    AssetMetadata(
        symbol="USDT",
        name="Tether / Toman",
        asset_class="crypto_fx",
        quote_currency="IRT",
        live_quote=True,
        forecast=True,
    ),
    AssetMetadata(
        symbol="GOLD18",
        name="18K Gold",
        asset_class="gold",
        quote_currency="IRT",
        live_quote=True,
        forecast=True,
    ),
    AssetMetadata(
        symbol="XAU",
        name="Gold Ounce",
        asset_class="metal",
        quote_currency="USD",
        live_quote=True,
        forecast=True,
    ),
    AssetMetadata(
        symbol="XAG",
        name="Silver Ounce",
        asset_class="metal",
        quote_currency="USD",
        live_quote=True,
        forecast=True,
    ),
    AssetMetadata(
        symbol="BTC",
        name="Bitcoin",
        asset_class="crypto",
        quote_currency="USDT",
        live_quote=True,
        forecast=True,
    ),
    AssetMetadata(
        symbol="ETH",
        name="Ethereum",
        asset_class="crypto",
        quote_currency="USDT",
        live_quote=True,
        forecast=True,
    ),
    *(AssetMetadata(
        symbol=symbol,
        name=name,
        asset_class="crypto",
        quote_currency="USD",
        live_quote=True,
        forecast=False,
    ) for symbol, name in TRACKED_CRYPTO_TOP20 if symbol not in {"BTC", "ETH", "USDT"}),
    *(AssetMetadata(
        symbol=symbol,
        name=name,
        asset_class="crypto",
        quote_currency="USDT",
        live_quote=True,
        forecast=False,
    ) for symbol, name in ADDITIONAL_WALLEX_ASSETS),
)
SUPPORTED_SYMBOLS = frozenset(asset.symbol for asset in SUPPORTED_ASSETS)


class MarketDataError(RuntimeError):
    def __init__(self, message: str, *, kind: str = "upstream") -> None:
        super().__init__(message)
        self.kind = kind


@dataclass(frozen=True)
class QuoteBatch:
    requested: tuple[str, ...]
    quotes: dict[str, MarketQuote]
    issues: dict[str, str]


class MarketDataService:
    """Backend market-data gateway.

    Phase 1 centralizes secrets/provider calls behind FastAPI. The Flutter app
    can migrate to this gateway incrementally in later phases.
    """

    _zarix_categories = {
        "XAU": "gold",
        "XAG": "gold",
        "BTC": "crypto",
        "ETH": "crypto",
    }
    _zarix_symbols = {
        "XAUUSD": "XAU",
        "XAGUSD": "XAG",
        "BTC": "BTC",
        "ETH": "ETH",
    }
    _navasan_symbols = {"USD": "usd_sell", "EUR": "eur", "GOLD18": "18ayar", "USDT": "usdt"}
    navasan_candle_symbols = frozenset(_navasan_symbols)
    _wallex_symbols = {
        **{symbol: f"{symbol}USDT" for symbol, _ in TRACKED_CRYPTO_ASSETS if symbol != "USDT"},
        "USDT": "USDTTMN",
    }
    wallex_candle_symbols = frozenset(_wallex_symbols)
    _wallex_candle_resolutions = {"1m": "1", "15m": "15", "1h": "60", "4h": "240", "1d": "1D"}
    _nobitex_pairs = {"BTC": ("btc", "usdt"), "USDT": ("usdt", "rls")}
    _gold_api_symbols = frozenset({"XAU", "XAG", "BTC", "ETH"})

    def __init__(self, settings: Settings, client: httpx.AsyncClient | None = None) -> None:
        self.settings = settings
        self._owns_client = client is None
        self.client = client or httpx.AsyncClient(
            timeout=httpx.Timeout(settings.market_timeout_seconds),
            headers={"accept": "application/json", "user-agent": "GoldBrain/phase1"},
            follow_redirects=False,
        )
        self._cache: dict[str, tuple[float, MarketQuote]] = {}
        self._navasan_lock = asyncio.Lock()
        self._navasan_last_attempt = 0.0
        self._navasan_month = datetime.now(timezone.utc).strftime("%Y-%m")
        self._navasan_requests_this_month = 0
        self._navasan_quotes: dict[str, MarketQuote] = {}
        self._navasan_last_history_attempt: dict[str, float] = {}
        self._navasan_sample_days: dict[tuple[str, date], tuple[float, list[MarketPriceSample]]] = {}
        if settings.navasan_api_key.strip():
            # Navasan documents query-string authentication. httpx's usual
            # request log includes the URL, so keep its transport loggers off.
            # Our sanitized provider telemetry below remains enabled.
            logging.getLogger("httpx").setLevel(logging.WARNING)
            logging.getLogger("httpcore").setLevel(logging.WARNING)
        self.coingecko = CoinGeckoProvider(
            self.client,
            base_url=settings.coingecko_base_url,
            demo_api_key=settings.coingecko_demo_api_key,
            min_quote_interval_seconds=settings.coingecko_min_quote_interval_seconds,
        )
        self._telemetry: list[dict[str, object]] = []
        self._telemetry_cursor = 0
        self.logger = logging.getLogger("goldbrain.market_data")

    async def close(self) -> None:
        if self._owns_client:
            await self.client.aclose()

    async def fetch_quotes(self, symbols: Iterable[str], force_refresh: bool = False) -> QuoteBatch:
        requested = tuple(dict.fromkeys(s.strip().upper() for s in symbols if s.strip()))
        quotes: dict[str, MarketQuote] = {}
        issues: dict[str, str] = {}
        pending: set[str] = set()
        stale_candidates: dict[str, MarketQuote] = {}
        now = time.monotonic()

        for symbol in requested:
            if symbol not in SUPPORTED_SYMBOLS:
                issues[symbol] = f"Unsupported market symbol: {symbol}"
                continue
            cached = self._cache.get(symbol)
            if (
                not force_refresh
                and cached is not None
                and now - cached[0] < self.settings.market_cache_seconds
                and classify_freshness(cached[1].provider_timestamp or cached[1].updated_at)
                not in {FreshnessStatus.STALE, FreshnessStatus.UNAVAILABLE}
            ):
                quotes[symbol] = cached[1]
            else:
                pending.add(symbol)

        if not pending:
            return QuoteBatch(requested=requested, quotes=quotes, issues=issues)

        # One public Wallex snapshot covers every active crypto pair. Pair
        # availability is checked per asset; a missing pair stays unresolved.
        iranian_crypto = pending.intersection(self._wallex_symbols)
        if iranian_crypto:
            started = time.perf_counter()
            try:
                wallex = await self._fetch_wallex()
                self._record_provider("wallex", "quotes", "success", started)
                for symbol in iranian_crypto:
                    if symbol in wallex:
                        quotes[symbol] = wallex[symbol]
                        pending.discard(symbol)
            except MarketDataError as exc:
                self._record_provider("wallex", "quotes", "error", started, error_kind=exc.kind)
                # Nobitex is an independent public fallback. An upstream outage
                # must never turn into an invented quote.
                fallback_started = time.perf_counter()
                try:
                    nobitex = await self._fetch_nobitex(iranian_crypto)
                    self._record_provider("nobitex", "quotes", "success", fallback_started, fallback_used=True)
                    for symbol in iranian_crypto:
                        if symbol in nobitex:
                            quotes[symbol] = nobitex[symbol].model_copy(
                                update={"fallback_from": "wallex", "quality_flags": ["fallback_provider"]}
                            )
                            pending.discard(symbol)
                except MarketDataError as exc:
                    self._record_provider("nobitex", "quotes", "error", fallback_started, error_kind=exc.kind, fallback_used=True)
                    pass

        # The public/demo endpoint provides a timestamped USD reference for
        # coins missing from the Iranian venue.
        # USDT/IRT is a different market and must never be substituted here.
        global_crypto = pending.intersection(COINGECKO_IDS) - {"USDT"}
        if global_crypto:
            started = time.perf_counter()
            try:
                reference = await self.coingecko.batch_quotes(global_crypto)
                self._record_provider("coingecko", "quotes", "success", started, fallback_used=True)
                for symbol in global_crypto:
                    quote = reference.get(symbol)
                    if quote is None:
                        continue
                    current_freshness = classify_freshness(quote.provider_timestamp).value
                    if current_freshness in {FreshnessStatus.STALE.value, FreshnessStatus.UNAVAILABLE.value}:
                        stale_candidates[symbol] = quote.model_copy(update={
                            "freshness_status": current_freshness, "freshness": current_freshness,
                        })
                    else:
                        quotes[symbol] = quote.model_copy(update={
                            "fallback_from": "wallex",
                            "quality_flags": ["fallback_provider"],
                        })
                        pending.discard(symbol)
            except CoinGeckoError as exc:
                self._record_provider("coingecko", "quotes", "error", started, error_kind=exc.kind, fallback_used=True)

        domestic = pending.intersection(self._navasan_symbols)
        if domestic and self.settings.navasan_api_key.strip():
            started = time.perf_counter()
            try:
                navasan = await self._fetch_navasan()
                self._record_provider("navasan", "quotes", "success", started)
                for symbol in domestic:
                    quote = navasan.get(symbol)
                    if quote is None:
                        continue
                    freshness = classify_freshness(quote.provider_timestamp).value
                    if freshness in {FreshnessStatus.STALE.value, FreshnessStatus.UNAVAILABLE.value}:
                        stale_candidates[symbol] = quote.model_copy(update={
                            "freshness_status": freshness, "freshness": freshness,
                            "quality_flags": [*quote.quality_flags, "stale_source"],
                        })
                        continue
                    quotes[symbol] = quote
                    pending.discard(symbol)
            except MarketDataError as exc:
                self._record_provider("navasan", "quotes", "error", started, error_kind=exc.kind)
                # The public fallback remains available. Never expose provider
                # secrets or raw upstream error bodies to the client.
                pass

        categories = {self._zarix_categories[s] for s in pending if s in self._zarix_categories}
        if categories:
            zarix_results = await asyncio.gather(
                *(self._safe_zarix(category) for category in categories)
            )
            for category, category_quotes, error in zarix_results:
                wanted = {s for s in pending if self._zarix_categories.get(s) == category}
                if error:
                    for symbol in wanted:
                        issues[symbol] = error
                    continue
                for symbol in wanted:
                    if symbol in category_quotes:
                        quotes[symbol] = category_quotes[symbol]
                        pending.discard(symbol)
                        issues.pop(symbol, None)

        fallback = pending.intersection(self._gold_api_symbols)
        if fallback:
            gold_results = await asyncio.gather(*(self._safe_gold_api(s) for s in fallback))
            for symbol, quote, error in gold_results:
                if quote is not None:
                    quotes[symbol] = quote
                    pending.discard(symbol)
                    issues.pop(symbol, None)
                elif error:
                    issues[symbol] = error

        for symbol in list(pending):
            if symbol in stale_candidates:
                quotes[symbol] = stale_candidates[symbol].model_copy(update={
                    "fallback_from": "wallex" if symbol in self._wallex_symbols else None,
                    "quality_flags": [*stale_candidates[symbol].quality_flags, "cached_last_known"],
                })
                issues[symbol] = f"Only stale last-known data is available for {symbol}."
                pending.discard(symbol)
            elif symbol in self._cache:
                previous = self._cache[symbol][1]
                quotes[symbol] = previous.model_copy(update={
                    "freshness_status": FreshnessStatus.STALE.value,
                    "freshness": FreshnessStatus.STALE.value,
                    "quality_flags": [*previous.quality_flags, "cached_last_known"],
                })
                issues[symbol] = f"Only stale last-known data is available for {symbol}."
                pending.discard(symbol)
        for symbol in pending:
            issues.setdefault(symbol, f"No live quote is currently available for {symbol}.")
        for symbol, quote in list(quotes.items()):
            preferred = (
                "wallex" if symbol in self._wallex_symbols
                else "navasan" if symbol in {"USD", "EUR", "GOLD18"}
                else "zarix"
            )
            if quote.provider != preferred and quote.fallback_from is None:
                quote = quote.model_copy(update={
                    "fallback_from": preferred,
                    "quality_flags": [*quote.quality_flags, "fallback_provider"],
                })
            quote = self._enrich_quote(quote)
            previous_cached = self._cache.get(symbol)
            if previous_cached and previous_cached[1].currency == quote.currency and previous_cached[1].price > 0:
                elapsed = (quote.updated_at - previous_cached[1].updated_at).total_seconds()
                jump_percent = abs(quote.price / previous_cached[1].price - 1.0) * 100
                if 0 <= elapsed < 60 and jump_percent > 20:
                    self.logger.warning(
                        "implausible_market_jump",
                        extra={"symbol": symbol, "provider": quote.provider, "jump_percent": jump_percent},
                    )
                    quote = quote.model_copy(update={
                        "data_quality_status": DataQualityStatus.SUSPECT.value,
                        "quality_flags": [*quote.quality_flags, "implausible_jump"],
                    })
            quotes[symbol] = quote
            self._cache[quote.symbol] = (time.monotonic(), quote)
        return QuoteBatch(requested=requested, quotes=quotes, issues=issues)

    async def fetch_coingecko_samples(
        self, *, symbol: str, timeframe: str, start_at: datetime, end_at: datetime,
    ) -> list[MarketCandle]:
        started = time.perf_counter()
        try:
            samples = await self.coingecko.price_samples(symbol, timeframe, start_at, end_at)
        except CoinGeckoError as exc:
            self._record_provider("coingecko", "price_samples", "error", started, error_kind=exc.kind, fallback_used=True)
            raise MarketDataError(str(exc), kind=exc.kind) from exc
        self._record_provider("coingecko", "price_samples", "success", started, fallback_used=True)
        return samples

    def observability_snapshot(self) -> list[dict[str, object]]:
        """Return sanitized in-process provider metrics for health/debug use."""
        return list(self._telemetry[-500:])

    def drain_observability(self) -> list[dict[str, object]]:
        new = self._telemetry[self._telemetry_cursor :]
        self._telemetry_cursor = len(self._telemetry)
        return list(new)

    async def cross_provider_check(self, symbol: str, primary: MarketQuote) -> MarketQuote:
        """Compare a primary quote with an independent source without averaging.

        The returned value remains the primary quote; a spread flag is attached
        when providers disagree materially.  This method is intentionally
        opt-in so the configured provider rate limits are respected.
        """
        normalized = symbol.strip().upper()
        if normalized not in self._nobitex_pairs:
            return primary
        secondary = await self._fetch_nobitex((normalized,))
        other = secondary.get(normalized)
        if other is None or other.price <= 0:
            return primary.model_copy(update={"quality_flags": [*primary.quality_flags, "secondary_unavailable"]})
        spread = abs(primary.price - other.price) / primary.price * 100
        flags = list(primary.quality_flags)
        if spread > 2.0:
            flags.append("provider_spread_exceeded")
        return primary.model_copy(update={"provider_spread_percent": spread, "quality_flags": flags})

    def _record_provider(self, provider: str, operation: str, status: str, started: float, *, error_kind: str | None = None, fallback_used: bool = False) -> None:
        item = {
            "provider": provider.lower(), "operation": operation.lower(), "status": status.lower(),
            "latency_ms": int(max(0.0, (time.perf_counter() - started) * 1000)),
            "error_kind": error_kind, "fallback_used": fallback_used,
            "observed_at": datetime.now(timezone.utc).isoformat(),
        }
        self._telemetry.append(item)
        self._telemetry = self._telemetry[-500:]
        self.logger.info("market_provider_request", extra={k: v for k, v in item.items() if k != "error_kind" or v})

    @staticmethod
    def _enrich_quote(quote: MarketQuote) -> MarketQuote:
        metadata = expected_metadata(quote.symbol)
        unit, currency, market = metadata or ("unknown", quote.currency, "unknown")
        received = quote.received_at or datetime.now(timezone.utc)
        provider_timestamp = quote.provider_timestamp
        flags = list(quote.quality_flags or [])
        if provider_timestamp is None and quote.provider in {"wallex", "nobitex", "zarix"}:
            # The snapshot or aggregator supplied no underlying source time.
            # Its update/receipt time cannot prove the market tick is live.
            flags.append("provider_timestamp_unavailable")
        effective_timestamp = provider_timestamp or quote.updated_at
        freshness = (
            FreshnessStatus.DELAYED.value
            if provider_timestamp is None and quote.provider in {"wallex", "nobitex", "zarix"}
            else classify_freshness(effective_timestamp).value
        )
        # Network latency and source-data age are separate measurements. Keep
        # latency null when a provider did not measure it instead of using the
        # source timestamp age as a misleading transport metric.
        latency = quote.latency_ms
        quality = quote.data_quality_status
        if quote.provider == "zarix" and quality == DataQualityStatus.VALID.value:
            quality = DataQualityStatus.UNVERIFIED.value
        return quote.model_copy(update={
            "asset": quote.symbol,
            "unit": quote.unit if quote.unit != "unknown" else unit,
            "currency": quote.currency or currency,
            "market": quote.market if quote.market != "unknown" else market,
            "provider_timestamp": provider_timestamp,
            "received_at": received,
            "latency_ms": latency,
            "freshness_status": freshness,
            "freshness": freshness,
            "data_quality_status": quality,
            "quality_flags": flags + (["provider_unverified"] if quality == DataQualityStatus.UNVERIFIED.value and "provider_unverified" not in flags else []),
        })

    async def _fetch_wallex(self) -> dict[str, MarketQuote]:
        base = self._https_base(self.settings.wallex_base_url, "Wallex")
        url = base.join("v1/markets")
        request_started = time.perf_counter()
        try:
            response = await self.client.get(str(url))
        except httpx.HTTPError as exc:
            raise MarketDataError("Wallex is temporarily unavailable.", kind="timeout" if isinstance(exc, httpx.TimeoutException) else "network") from exc
        body = self._json_object(response, "Wallex")
        request_latency_ms = int((time.perf_counter() - request_started) * 1000)
        result = body.get("result")
        symbols = result.get("symbols") if isinstance(result, dict) else None
        if not isinstance(symbols, dict):
            raise MarketDataError("Wallex returned invalid market data.")

        quotes: dict[str, MarketQuote] = {}
        for symbol, market_symbol in self._wallex_symbols.items():
            market = symbols.get(market_symbol)
            if not isinstance(market, dict):
                continue
            stats = market.get("stats")
            if not isinstance(stats, dict):
                continue
            price = self._positive_number(stats.get("lastPrice"))
            if price is None:
                continue
            quotes[symbol] = MarketQuote(
                symbol=symbol,
                name=str(market.get("faBaseAsset") or symbol),
                currency="IRT" if symbol == "USDT" else "USDT",
                price=price,
                # The public market snapshot has no per-ticker timestamp; the
                # backend records the exact time it received this response.
                updated_at=datetime.now(timezone.utc),
                provider="wallex",
                latency_ms=request_latency_ms,
                change_percent=self._number(stats.get("24h_ch")),
                upstream_source=market_symbol,
            )
        if not quotes:
            raise MarketDataError("Wallex returned no supported quotes.")
        return quotes

    async def fetch_wallex_candles(
        self,
        *,
        symbol: str,
        timeframe: str,
        start_at: datetime,
        end_at: datetime,
    ) -> list[MarketCandle]:
        """Fetch public Wallex OHLCV for configured active crypto markets.

        Gold18 is not a Wallex market; its history remains derived from verified
        stored quotes until a licensed Iranian-gold history provider is chosen.
        """
        normalized_symbol = symbol.strip().upper()
        normalized_timeframe = timeframe.strip().lower()
        market_symbol = self._wallex_symbols.get(normalized_symbol)
        resolution = self._wallex_candle_resolutions.get(normalized_timeframe)
        if market_symbol is None or resolution is None:
            raise MarketDataError("Wallex candle history is unavailable for this symbol or timeframe.")
        start = _utc(start_at)
        end = _utc(end_at)
        if end <= start:
            raise MarketDataError("Candle history end time must be after start time.")
        base = self._https_base(self.settings.wallex_base_url, "Wallex")
        request_started = time.perf_counter()
        try:
            response = await self.client.get(
                str(base.join("v1/udf/history")),
                params={
                    "symbol": market_symbol,
                    "resolution": resolution,
                    "from": int(start.timestamp()),
                    "to": int(end.timestamp()),
                },
            )
        except httpx.HTTPError as exc:
            raise MarketDataError("Wallex candle history is temporarily unavailable.", kind="timeout" if isinstance(exc, httpx.TimeoutException) else "network") from exc
        body = self._json_object(response, "Wallex")
        request_latency_ms = int((time.perf_counter() - request_started) * 1000)
        if body.get("s") != "ok":
            raise MarketDataError("Wallex returned no usable candle history.")
        timestamps, opens, highs, lows, closes, volumes = (
            body.get("t"), body.get("o"), body.get("h"), body.get("l"), body.get("c"), body.get("v")
        )
        values = (timestamps, opens, highs, lows, closes, volumes)
        if not all(isinstance(value, list) for value in values):
            raise MarketDataError("Wallex returned invalid candle history.")
        timestamp_values = cast(list[object], timestamps)
        open_values = cast(list[object], opens)
        high_values = cast(list[object], highs)
        low_values = cast(list[object], lows)
        close_values = cast(list[object], closes)
        volume_values = cast(list[object], volumes)
        if len({len(value) for value in (timestamp_values, open_values, high_values, low_values, close_values, volume_values)}) != 1:
            raise MarketDataError("Wallex returned invalid candle history.")
        delta = {
            "1m": timedelta(minutes=1),
            "15m": timedelta(minutes=15),
            "1h": timedelta(hours=1),
            "4h": timedelta(hours=4),
            "1d": timedelta(days=1),
        }[normalized_timeframe]
        candles: list[MarketCandle] = []
        for timestamp, opening, high, low, close, volume in zip(
            timestamp_values, open_values, high_values, low_values, close_values, volume_values, strict=True
        ):
            unix_time = self._positive_number(timestamp)
            open_price = self._positive_number(opening)
            high_price = self._positive_number(high)
            low_price = self._positive_number(low)
            close_price = self._positive_number(close)
            parsed_volume = self._number(volume)
            if (
                unix_time is None
                or open_price is None
                or high_price is None
                or low_price is None
                or close_price is None
                or (parsed_volume is not None and parsed_volume < 0)
            ):
                raise MarketDataError("Wallex returned invalid candle values.")
            opened_at = datetime.fromtimestamp(unix_time, tz=timezone.utc)
            if opened_at < start - delta or opened_at > end:
                raise MarketDataError("Wallex returned candles outside the requested range.")
            candles.append(
                MarketCandle(
                    symbol=normalized_symbol,
                    timeframe=normalized_timeframe,
                    currency="IRT" if normalized_symbol == "USDT" else "USDT",
                    provider="wallex",
                    upstream_source=market_symbol,
                    opened_at=opened_at,
                    closed_at=opened_at + delta,
                    open=open_price,
                    high=high_price,
                    low=low_price,
                    close=close_price,
                    volume=parsed_volume,
                    provider_timestamp=opened_at,
                    received_at=datetime.now(timezone.utc),
                    latency_ms=request_latency_ms,
                    freshness_status=FreshnessStatus.FRESH.value,
                    data_quality_status=DataQualityStatus.VALID.value,
                )
            )
        return candles

    async def _fetch_nobitex(self, wanted: Iterable[str]) -> dict[str, MarketQuote]:
        base = self._https_base(self.settings.nobitex_base_url, "Nobitex")
        quotes: dict[str, MarketQuote] = {}
        for symbol in wanted:
            pair = self._nobitex_pairs.get(symbol)
            if pair is None:
                continue
            request_started = time.perf_counter()
            try:
                response = await self.client.get(
                    str(base.join("market/stats")),
                    params={"srcCurrency": pair[0], "dstCurrency": pair[1]},
                )
            except httpx.HTTPError as exc:
                raise MarketDataError("Nobitex is temporarily unavailable.", kind="timeout" if isinstance(exc, httpx.TimeoutException) else "network") from exc
            body = self._json_object(response, "Nobitex")
            request_latency_ms = int((time.perf_counter() - request_started) * 1000)
            stats = body.get("stats")
            if body.get("status") != "ok" or not isinstance(stats, dict):
                continue
            market = stats.get(f"{pair[0]}-{pair[1]}")
            if not isinstance(market, dict):
                continue
            price = self._positive_number(market.get("latest"))
            if price is None:
                continue
            # Nobitex's rls market is quoted in rial; normalize once at the
            # provider boundary to the canonical IRT (toman) representation.
            if symbol == "USDT":
                normalized = normalize_iranian_price(price, "IRR")
                if normalized is None:
                    continue
                price, _ = normalized
            quotes[symbol] = MarketQuote(
                symbol=symbol,
                name=symbol,
                currency="USDT" if symbol == "BTC" else "IRT",
                price=price,
                updated_at=datetime.now(timezone.utc),
                provider="nobitex",
                latency_ms=request_latency_ms,
                change_percent=self._number(market.get("dayChange")),
                upstream_source=f"{pair[0]}-{pair[1]}",
            )
        if not quotes:
            raise MarketDataError("Nobitex returned no supported quotes.")
        return quotes

    async def _fetch_navasan(self) -> dict[str, MarketQuote]:
        async with self._navasan_lock:
            now = time.monotonic()
            if (
                self._navasan_last_attempt
                and now - self._navasan_last_attempt < self.settings.navasan_min_quote_interval_seconds
            ):
                if self._navasan_quotes:
                    return dict(self._navasan_quotes)
                raise MarketDataError("Navasan development poll interval has not elapsed.", kind="throttled")
            self._reserve_navasan_request()
            self._navasan_last_attempt = now
            base = self._https_base(self.settings.navasan_base_url, "Navasan")
            request_started = time.perf_counter()
            try:
                response = await self.client.get(
                    str(base.join("latest/")), params={"api_key": self.settings.navasan_api_key}
                )
            except httpx.HTTPError as exc:
                kind = "timeout" if isinstance(exc, httpx.TimeoutException) else "network"
                raise MarketDataError("Navasan is temporarily unavailable.", kind=kind) from exc
            body = self._json_object(response, "Navasan")
            request_latency_ms = int((time.perf_counter() - request_started) * 1000)
            received_at = datetime.now(timezone.utc)
            quotes: dict[str, MarketQuote] = {}
            for symbol, upstream in self._navasan_symbols.items():
                raw = body.get(upstream)
                if not isinstance(raw, dict):
                    continue
                unit, _, market = expected_metadata(symbol) or ("unknown", "IRT", "IRAN")
                upstream_currency = str(raw.get("currency") or "IRT").strip().upper()
                upstream_unit = str(raw.get("unit") or unit).strip().lower()
                if upstream_unit != unit.lower():
                    continue
                normalized = normalize_iranian_price(raw.get("value"), upstream_currency)
                price = normalized[0] if normalized is not None else None
                updated_at = self._unix_date(raw.get("timestamp"))
                if price is None or updated_at is None or updated_at > received_at + timedelta(seconds=30):
                    continue
                change = self._number(raw.get("change"))
                if change is not None and upstream_currency in {"IRR", "RLS", "RIAL"}:
                    change /= 10
                previous = None if change is None else price - change
                change_pct = None if change is None or previous is None or previous <= 0 else (change / previous) * 100
                freshness = classify_freshness(updated_at, now=received_at).value
                verified_unit = symbol in {"USD", "EUR", "GOLD18"}
                quotes[symbol] = MarketQuote(
                    asset=symbol, symbol=symbol, name=symbol,
                    currency="IRT", price=price, updated_at=updated_at,
                    provider="navasan", provider_timestamp=updated_at,
                    received_at=received_at, latency_ms=request_latency_ms,
                    freshness_status=freshness, freshness=freshness,
                    data_quality_status=(DataQualityStatus.VALID.value if verified_unit
                                         else DataQualityStatus.UNVERIFIED.value),
                    quality_flags=[] if verified_unit else ["unit_from_provider_catalog"],
                    unit=unit, market=market,
                    change_percent=change_pct, upstream_source=upstream,
                )
            if not quotes:
                raise MarketDataError("Navasan returned no usable quotes.")
            self._navasan_quotes = quotes
            return dict(quotes)

    def _reserve_navasan_request(self) -> None:
        month = datetime.now(timezone.utc).strftime("%Y-%m")
        if month != self._navasan_month:
            self._navasan_month = month
            self._navasan_requests_this_month = 0
        if self._navasan_requests_this_month >= self.settings.navasan_monthly_request_budget:
            raise MarketDataError("Navasan development request budget is exhausted.", kind="quota")
        self._navasan_requests_this_month += 1

    async def fetch_navasan_intraday_samples(
        self, *, symbol: str, start_at: datetime, end_at: datetime,
    ) -> list[MarketPriceSample]:
        """Return only observed /dailyCurrency prices; never synthesize OHLC."""
        symbol = symbol.strip().upper()
        code = self._navasan_symbols.get(symbol) if symbol in {"USD", "GOLD18"} else None
        start, end = _utc(start_at), _utc(end_at)
        if not self.settings.navasan_api_key.strip() or code is None or end <= start:
            raise MarketDataError("Navasan intraday history is not configured for this asset.", kind="unsupported")
        if end - start > timedelta(hours=25):
            raise MarketDataError("Navasan intraday sample range exceeds 25 hours.", kind="invalid_range")
        tehran = ZoneInfo("Asia/Tehran")
        first_day = start.astimezone(tehran).date()
        last_day = end.astimezone(tehran).date()
        days = (first_day,) if first_day == last_day else (first_day, last_day)
        samples: list[MarketPriceSample] = []
        failures: list[MarketDataError] = []
        for day in days:
            try:
                samples.extend(await self._fetch_navasan_sample_day(symbol, code, day, tehran))
            except MarketDataError as exc:
                failures.append(exc)
        if not samples and failures:
            raise failures[0]
        by_timestamp: dict[datetime, MarketPriceSample] = {}
        for sample in samples:
            if start <= sample.provider_timestamp <= end:
                previous = by_timestamp.get(sample.provider_timestamp)
                if previous is not None and previous.price != sample.price:
                    raise MarketDataError("Navasan returned conflicting intraday prices.", kind="duplicate")
                by_timestamp[sample.provider_timestamp] = sample
        received_now = datetime.now(timezone.utc)
        return [
            by_timestamp[timestamp].model_copy(update={
                "freshness_status": classify_freshness(timestamp, now=received_now).value,
                "quality_flags": [
                    *by_timestamp[timestamp].quality_flags,
                    *(["partial_provider_history"] if failures else []),
                ],
            })
            for timestamp in sorted(by_timestamp)
        ]

    async def _fetch_navasan_sample_day(
        self, symbol: str, code: str, day: date, tehran: ZoneInfo,
    ) -> list[MarketPriceSample]:
        cache_key = (symbol, day)
        async with self._navasan_lock:
            cached = self._navasan_sample_days.get(cache_key)
            now = datetime.now(timezone.utc)
            is_today = day == now.astimezone(tehran).date()
            cache_seconds = self.settings.navasan_min_quote_interval_seconds if is_today else 86400
            if cached and time.monotonic() - cached[0] < cache_seconds:
                return list(cached[1])
            self._reserve_navasan_request()
            base = self._https_base(self.settings.navasan_base_url, "Navasan")
            try:
                response = await self.client.get(
                    str(base.join("dailyCurrency/")),
                    params={"api_key": self.settings.navasan_api_key, "item": code,
                            "date": _navasan_jalali_date(day)},
                )
            except httpx.HTTPError as exc:
                kind = "timeout" if isinstance(exc, httpx.TimeoutException) else "network"
                raise MarketDataError("Navasan intraday history is unavailable.", kind=kind) from exc
            if response.status_code == 429:
                raise MarketDataError("Navasan intraday history quota is exhausted.", kind="rate_limit")
            if response.status_code != 200:
                raise MarketDataError("Navasan intraday history request failed.", kind="upstream")
            try:
                body = response.json()
            except ValueError as exc:
                raise MarketDataError("Navasan returned invalid intraday JSON.") from exc
            if not isinstance(body, list):
                raise MarketDataError("Navasan returned invalid intraday samples.")
            received_at = datetime.now(timezone.utc)
            unit, _, market = expected_metadata(symbol) or ("unknown", "IRT", "IRAN")
            samples: list[MarketPriceSample] = []
            for row in body:
                if not isinstance(row, dict):
                    continue
                timestamp = self._unix_date(row.get("timestamp"))
                raw_currency = str(row.get("currency") or "IRT").strip().upper()
                normalized = normalize_iranian_price(row.get("value"), raw_currency)
                price = normalized[0] if normalized is not None else None
                if (timestamp is None or price is None or timestamp > received_at + timedelta(seconds=30)
                        or timestamp.astimezone(tehran).date() != day
                        or str(row.get("unit") or unit).strip().lower() != unit.lower()):
                    continue
                samples.append(MarketPriceSample(
                    symbol=symbol, price=price, currency="IRT", unit=unit, market=market,
                    provider="navasan", upstream_source=code,
                    provider_timestamp=timestamp, received_at=received_at,
                    freshness_status=classify_freshness(timestamp, now=received_at).value,
                    data_quality_status=DataQualityStatus.VALID.value,
                    quality_flags=["price_sample_not_ohlc"],
                ))
            self._navasan_sample_days[cache_key] = (time.monotonic(), samples)
            return list(samples)

    async def fetch_navasan_daily_candles(
        self, *, symbol: str, start_at: datetime, end_at: datetime,
    ) -> list[MarketCandle]:
        """Read documented daily OHLC without inventing intraday candles.

        This path requires a Navasan key and returns provider-labelled daily
        sessions, never inferred hourly candles.
        """
        symbol = symbol.strip().upper()
        code = self._navasan_symbols.get(symbol)
        start, end = _utc(start_at), _utc(end_at)
        if not self.settings.navasan_api_key.strip() or code is None or end <= start:
            raise MarketDataError("Navasan daily history is not configured for this asset.", kind="unsupported")
        if end - start > timedelta(days=40):
            raise MarketDataError("Navasan daily history range exceeds 40 days.", kind="invalid_range")
        async with self._navasan_lock:
            now = time.monotonic()
            previous = self._navasan_last_history_attempt.get(symbol, 0.0)
            if previous and now - previous < self.settings.navasan_min_quote_interval_seconds:
                return []
            self._reserve_navasan_request()
            self._navasan_last_history_attempt[symbol] = now
            base = self._https_base(self.settings.navasan_base_url, "Navasan")
            started = time.perf_counter()
            try:
                response = await self.client.get(
                    str(base.join("ohlcSearch/")),
                    params={
                        "api_key": self.settings.navasan_api_key,
                        "item": code,
                        "start": int(start.timestamp()),
                        "end": int(end.timestamp()),
                    },
                )
            except httpx.HTTPError as exc:
                kind = "timeout" if isinstance(exc, httpx.TimeoutException) else "network"
                raise MarketDataError("Navasan daily history is unavailable.", kind=kind) from exc
            if response.status_code == 429:
                raise MarketDataError("Navasan daily history quota is exhausted.", kind="rate_limit")
            if response.status_code != 200:
                raise MarketDataError("Navasan daily history request failed.")
            try:
                body = response.json()
            except ValueError as exc:
                raise MarketDataError("Navasan returned invalid daily history JSON.") from exc
            rows = body if isinstance(body, list) else body.get("data") if isinstance(body, dict) else None
            if not isinstance(rows, list):
                raise MarketDataError("Navasan daily history response shape is unverified.")
            received_at = datetime.now(timezone.utc)
            latency_ms = int((time.perf_counter() - started) * 1000)
            tehran = ZoneInfo("Asia/Tehran")
            unit, _, market = expected_metadata(symbol) or ("unknown", "IRT", "IRAN")
            candles: list[MarketCandle] = []
            seen_days: set[object] = set()
            for row in rows:
                if not isinstance(row, dict):
                    continue
                observed = self._unix_date(row.get("timestamp"))
                raw_currency = str(row.get("currency") or "IRT").strip().upper()
                if str(row.get("unit") or unit).strip().lower() != unit.lower():
                    continue
                normalized_prices = [normalize_iranian_price(row.get(field), raw_currency)
                                     for field in ("open", "high", "low", "close")]
                if (observed is None or observed > received_at + timedelta(seconds=30)
                        or any(value is None for value in normalized_prices)):
                    continue
                opening, high, low, close = (value[0] for value in normalized_prices if value is not None)
                if high < max(opening, close, low) or low > min(opening, close, high):
                    continue
                day = observed.astimezone(tehran).date()
                if day in seen_days:
                    raise MarketDataError("Navasan returned duplicate daily candles.", kind="duplicate")
                seen_days.add(day)
                opened = datetime.combine(day, datetime.min.time(), tzinfo=tehran).astimezone(timezone.utc)
                closed = datetime.combine(day + timedelta(days=1), datetime.min.time(), tzinfo=tehran).astimezone(timezone.utc)
                if opened < start - timedelta(days=1) or opened >= end + timedelta(days=1):
                    continue
                candles.append(MarketCandle(
                    symbol=symbol, timeframe="1d", currency="IRT", provider="navasan",
                    upstream_source=code, opened_at=opened, closed_at=closed,
                    open=opening, high=high, low=low, close=close, volume=None,
                    unit=unit, market=market, provider_timestamp=observed,
                    received_at=received_at, latency_ms=latency_ms,
                    freshness_status=classify_freshness(observed, now=received_at).value,
                    data_quality_status=(DataQualityStatus.VALID.value if symbol in {"USD", "EUR", "GOLD18"}
                                         else DataQualityStatus.UNVERIFIED.value),
                    quality_flags=(["daily_session_from_timestamp"] if symbol in {"USD", "EUR", "GOLD18"}
                                   else ["unit_from_provider_catalog", "daily_session_from_timestamp"]),
                    is_complete=closed <= received_at,
                ))
            return sorted(candles, key=lambda candle: candle.opened_at)

    async def _safe_zarix(self, category: str) -> tuple[str, dict[str, MarketQuote], str | None]:
        started = time.perf_counter()
        try:
            result = await self._fetch_zarix(category)
            self._record_provider("zarix", f"quotes:{category}", "success", started, fallback_used=True)
            return category, result, None
        except MarketDataError as exc:
            self._record_provider("zarix", f"quotes:{category}", "error", started, error_kind=exc.kind, fallback_used=True)
            return category, {}, "ZARIX is temporarily unavailable for this market."

    async def _fetch_zarix(self, category: str) -> dict[str, MarketQuote]:
        base = self._https_base(self.settings.zarix_base_url, "ZARIX")
        request_started = time.perf_counter()
        try:
            response = await self.client.get(
                str(base),
                params={"endpoint": "markets", "category": category, "page": 1, "limit": 100},
            )
        except httpx.HTTPError as exc:
            raise MarketDataError("ZARIX is temporarily unavailable.", kind="timeout" if isinstance(exc, httpx.TimeoutException) else "network") from exc
        body = self._json_object(response, "ZARIX")
        request_latency_ms = int((time.perf_counter() - request_started) * 1000)
        if body.get("ok") is not True:
            raise MarketDataError("ZARIX returned an unsuccessful response.")
        data = body.get("data")
        items = data.get("items") if isinstance(data, dict) else None
        if not isinstance(items, list):
            raise MarketDataError("ZARIX returned invalid market data.")
        quotes: dict[str, MarketQuote] = {}
        for item in items:
            if not isinstance(item, dict):
                continue
            raw_symbol = str(item.get("symbol") or "").strip().upper()
            symbol = self._zarix_symbols.get(raw_symbol)
            if symbol is None:
                continue
            price = self._positive_number(item.get("price"))
            source_time = self._date(item.get("sourceTime"))
            updated = source_time or self._date(item.get("updatedAt"))
            currency = self._zarix_currency(item.get("unit"), symbol)
            if price is None or updated is None or currency is None or not self._is_fresh(updated):
                continue
            quotes[symbol] = MarketQuote(
                symbol=symbol,
                name=str(item.get("title") or symbol).strip() or symbol,
                currency=currency,
                price=price,
                updated_at=updated,
                provider="zarix",
                provider_timestamp=source_time,
                latency_ms=request_latency_ms,
                change_percent=self._number(item.get("changePercent")),
                upstream_source=(str(item.get("source") or "").strip() or None),
            )
        if not quotes:
            raise MarketDataError("ZARIX returned no supported quotes.")
        return quotes

    async def _safe_gold_api(self, symbol: str) -> tuple[str, MarketQuote | None, str | None]:
        started = time.perf_counter()
        try:
            result = await self._fetch_gold_api(symbol)
            self._record_provider("gold-api", "quote", "success", started, fallback_used=True)
            return symbol, result, None
        except MarketDataError as exc:
            self._record_provider("gold-api", "quote", "error", started, error_kind=exc.kind, fallback_used=True)
            return symbol, None, f"Gold API is temporarily unavailable for {symbol}."

    async def _fetch_gold_api(self, symbol: str) -> MarketQuote:
        base = self._https_base(self.settings.gold_api_base_url, "Gold API")
        url = base.join(f"price/{symbol}")
        request_started = time.perf_counter()
        try:
            response = await self.client.get(str(url))
        except httpx.HTTPError as exc:
            raise MarketDataError("Gold API is temporarily unavailable.", kind="timeout" if isinstance(exc, httpx.TimeoutException) else "network") from exc
        body = self._json_object(response, "Gold API")
        request_latency_ms = int((time.perf_counter() - request_started) * 1000)
        price = self._positive_number(body.get("price"))
        updated = self._date(body.get("updatedAt"))
        returned_symbol = str(body.get("symbol") or symbol).upper()
        if price is None or updated is None or returned_symbol != symbol or not self._is_fresh(updated):
            raise MarketDataError("Gold API returned invalid price data.")
        return MarketQuote(
            symbol=symbol,
            name=str(body.get("name") or symbol),
            currency=str(body.get("currency") or "USD").upper(),
            price=price,
            updated_at=updated,
            provider="gold-api",
            provider_timestamp=updated,
            latency_ms=request_latency_ms,
            upstream_source="gold-api.com",
        )

    def _json_object(self, response: httpx.Response, provider: str) -> dict:
        if response.status_code < 200 or response.status_code >= 300:
            kind = "rate_limit" if response.status_code == 429 else "timeout" if response.status_code in {408, 504} else "upstream"
            raise MarketDataError(f"{provider} request failed.", kind=kind)
        try:
            body = response.json()
        except ValueError as exc:
            raise MarketDataError(f"{provider} returned invalid JSON.") from exc
        if not isinstance(body, dict):
            raise MarketDataError(f"{provider} returned invalid JSON.")
        return body

    def _https_base(self, raw: str, provider: str) -> httpx.URL:
        url = httpx.URL(raw)
        if url.scheme != "https":
            raise MarketDataError(f"{provider} endpoint must use HTTPS.")
        return url

    @staticmethod
    def _positive_number(value: object) -> float | None:
        try:
            parsed = float(str(value).replace(",", "").strip())
        except (TypeError, ValueError):
            return None
        return parsed if math.isfinite(parsed) and parsed > 0 else None

    @staticmethod
    def _number(value: object) -> float | None:
        if value is None or str(value).strip() == "":
            return None
        try:
            parsed = float(str(value).replace(",", "").strip())
        except (TypeError, ValueError):
            return None
        return parsed if math.isfinite(parsed) else None

    @staticmethod
    def _date(value: object) -> datetime | None:
        if not isinstance(value, str) or not value.strip():
            return None
        normalized = value.strip().replace("Z", "+00:00")
        try:
            parsed = datetime.fromisoformat(normalized)
        except ValueError:
            return None
        if parsed.tzinfo is None:
            parsed = parsed.replace(tzinfo=timezone.utc)
        return parsed.astimezone(timezone.utc)

    @staticmethod
    def _unix_date(value: object) -> datetime | None:
        try:
            timestamp = float(str(value))
        except (TypeError, ValueError):
            return None
        if not math.isfinite(timestamp) or timestamp <= 0:
            return None
        # JavaScript APIs conventionally publish milliseconds; accept seconds
        # as well so a documented provider migration does not silently shift
        # the quote date by a thousand-fold.
        if timestamp > 10_000_000_000:
            timestamp /= 1000
        try:
            return datetime.fromtimestamp(timestamp, tz=timezone.utc)
        except (OverflowError, OSError, ValueError):
            return None

    def _is_fresh(self, updated_at: datetime) -> bool:
        age = (datetime.now(timezone.utc) - updated_at).total_seconds()
        # Future timestamps are rejected too: a provider clock problem must not
        # be interpreted as a fresh market quote.
        return 0 <= age <= self.settings.market_max_quote_age_seconds

    @staticmethod
    def _zarix_currency(unit: object, symbol: str) -> str | None:
        normalized = str(unit or "").strip().upper()
        if symbol in {"BTC", "ETH"} and normalized == "USDT":
            return "USDT"
        if symbol in {"XAU", "XAG"} and ("دلار" in str(unit or "") or "USD" in normalized):
            return "USD"
        return None


def _utc(value: datetime) -> datetime:
    if value.tzinfo is None:
        return value.replace(tzinfo=timezone.utc)
    return value.astimezone(timezone.utc)


def _navasan_jalali_date(day: date) -> str:
    """Format a Tehran calendar day for Navasan's working Jalali date form."""
    gy, gm, gd = day.year, day.month, day.day
    cumulative = (0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334)
    year = gy - 1600
    month = gm - 1
    day_number = (
        365 * year + (year + 3) // 4 - (year + 99) // 100
        + (year + 399) // 400 + cumulative[month] + gd - 1
    )
    if month > 1 and (gy % 4 == 0 and gy % 100 != 0 or gy % 400 == 0):
        day_number += 1
    jalali_days = day_number - 79
    cycles, jalali_days = divmod(jalali_days, 12053)
    jy = 979 + 33 * cycles + 4 * (jalali_days // 1461)
    jalali_days %= 1461
    if jalali_days >= 366:
        extra, jalali_days = divmod(jalali_days - 1, 365)
        jy += extra
    if jalali_days < 186:
        jm, jd = 1 + jalali_days // 31, 1 + jalali_days % 31
    else:
        jm, jd = 7 + (jalali_days - 186) // 30, 1 + (jalali_days - 186) % 30
    return f"{jy:04d}-{jm:02d}-{jd:02d}"
