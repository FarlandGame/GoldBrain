"""Canonical market-data metadata and validation helpers.

The API treats provenance and units as part of the value.  Callers should
never infer whether a price is rial, toman, USDT or USD from a symbol alone.
"""
from __future__ import annotations

import math
from datetime import datetime, timezone
from enum import StrEnum


class FreshnessStatus(StrEnum):
    LIVE = "LIVE"
    FRESH = "FRESH"
    DELAYED = "DELAYED"
    STALE = "STALE"
    UNAVAILABLE = "UNAVAILABLE"


class DataQualityStatus(StrEnum):
    VALID = "VALID"
    UNVERIFIED = "UNVERIFIED"
    SUSPECT = "SUSPECT"
    INVALID = "INVALID"

# Snapshot of the 20 largest tracked crypto assets on 2026-09-25. The set is
# intentionally dated; market-cap ranks need periodic review.
TRACKED_CRYPTO_TOP20: tuple[tuple[str, str], ...] = (
    ("BTC", "Bitcoin"), ("ETH", "Ethereum"), ("USDT", "Tether"),
    ("BNB", "BNB"), ("XRP", "XRP"), ("USDC", "USD Coin"),
    ("SOL", "Solana"), ("TRX", "TRON"), ("ZEC", "Zcash"),
    ("HYPE", "Hyperliquid"), ("DOGE", "Dogecoin"), ("XMR", "Monero"),
    ("LINK", "Chainlink"), ("ADA", "Cardano"), ("LEO", "UNUS SED LEO"),
    ("XLM", "Stellar"), ("BCH", "Bitcoin Cash"), ("NEAR", "NEAR Protocol"),
    ("UNI", "Uniswap"), ("LTC", "Litecoin"),
)

# Extra assets explicitly requested from the Wallex screenshot (2026-10-17).
# Keep the dated top-20 snapshot above unchanged; these are additions, not ranks.
ADDITIONAL_WALLEX_ASSETS: tuple[tuple[str, str], ...] = (
    ("DOT", "Polkadot"), ("PAXG", "PAX Gold"), ("NOT", "Notcoin"),
    ("AVAX", "Avalanche"), ("TON", "Toncoin"), ("PEPE", "Pepe"),
    ("ARB", "Arbitrum"),
)
TRACKED_CRYPTO_ASSETS = TRACKED_CRYPTO_TOP20 + ADDITIONAL_WALLEX_ASSETS

ASSET_UNITS: dict[str, tuple[str, str, str]] = {
    "BTC": ("coin", "USDT", "GLOBAL"),
    "USDT": ("coin", "IRT", "IRAN"),
    "GOLD18": ("gram_18k", "IRT", "IRAN"),
    "USD": ("currency_unit", "IRT", "IRAN"),
    "XAU": ("troy_ounce", "USD", "GLOBAL"),
    "XAG": ("troy_ounce", "USD", "GLOBAL"),
    "ETH": ("coin", "USDT", "GLOBAL"),
    "EUR": ("currency_unit", "IRT", "IRAN"),
    **{
        symbol: ("coin", "USD", "GLOBAL")
        for symbol, _ in TRACKED_CRYPTO_TOP20
        if symbol not in {"BTC", "ETH", "USDT"}
    },
    **{symbol: ("coin", "USDT", "GLOBAL") for symbol, _ in ADDITIONAL_WALLEX_ASSETS},
}


def excluded_domestic_reference_providers(symbol: str) -> tuple[str, ...]:
    """Exclude old persisted reference quotes that were mislabelled as domestic markets."""
    normalized = symbol.strip().upper()
    if normalized == "GOLD18":
        return ("persian-toolbox", "zarix")
    if normalized in {"USD", "EUR"}:
        return ("zarix",)
    return ()


def allowed_currencies(symbol: str) -> frozenset[str]:
    normalized = symbol.strip().upper()
    if normalized in {item[0] for item in TRACKED_CRYPTO_ASSETS} and normalized != "USDT":
        # Venue quotes are USDT; data aggregators quote USD. They remain
        # separate, explicitly labelled series.
        return frozenset({"USD", "USDT"})
    metadata = expected_metadata(normalized)
    return frozenset({metadata[1]}) if metadata else frozenset()


def normalize_iranian_price(value: object, currency: str) -> tuple[float, str] | None:
    """Normalize an Iranian market price to GoldBrain's canonical IRT (toman).

    Providers commonly publish either rial (IRR) or toman (IRT).  The unit is
    converted once at the provider boundary and the canonical currency is
    carried with the value so downstream code never guesses.
    """
    try:
        number = float(str(value).replace(",", "").strip())
    except (TypeError, ValueError):
        return None
    if not math.isfinite(number) or number <= 0:
        return None
    normalized = str(currency).strip().upper()
    if normalized in {"IRR", "RLS", "RIAL"}:
        number /= 10.0
    elif normalized not in {"IRT", "TOMAN", "TMN"}:
        return None
    return number, "IRT"


def utc(value: datetime) -> datetime:
    if value.tzinfo is None:
        return value.replace(tzinfo=timezone.utc)
    return value.astimezone(timezone.utc)


def classify_freshness(
    observed_at: datetime | None,
    *,
    now: datetime | None = None,
    fresh_after_seconds: int = 120,
    delayed_after_seconds: int = 300,
) -> FreshnessStatus:
    if observed_at is None:
        return FreshnessStatus.UNAVAILABLE
    age = (utc(now or datetime.now(timezone.utc)) - utc(observed_at)).total_seconds()
    if age < 0:
        return FreshnessStatus.STALE
    if age <= fresh_after_seconds:
        return FreshnessStatus.LIVE
    if age <= delayed_after_seconds:
        return FreshnessStatus.FRESH
    if age <= max(delayed_after_seconds * 3, 900):
        return FreshnessStatus.DELAYED
    return FreshnessStatus.STALE


def expected_metadata(symbol: str) -> tuple[str, str, str] | None:
    return ASSET_UNITS.get(symbol.strip().upper())


def validate_price(price: object) -> float | None:
    try:
        number = float(str(price))
    except (TypeError, ValueError):
        return None
    return number if math.isfinite(number) and number > 0 else None
