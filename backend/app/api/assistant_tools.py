from __future__ import annotations

from datetime import datetime, timedelta, timezone
import re

import httpx
from fastapi import HTTPException
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.orm import Session

from app.api.routes.history import asset_candles, asset_price_samples
from app.api.routes.market import quotes
from app.core.market_quality import allowed_currencies, expected_metadata, validate_price
from app.services.assistant import utc
from app.services.market_data import SUPPORTED_ASSETS, MarketDataService


def currency_labels(currency: str) -> dict:
    names = {"IRT": ("Toman", "تومان"), "IRR": ("Rial", "ریال"),
             "USD": ("US dollar", "دلار آمریکا"), "USDT": ("Tether", "تتر")}
    english, persian = names.get(currency, (currency, currency))
    return {"currency_name": english, "currency_name_fa": persian}


class AssistantDataTools:
    """Read-only tools use the same bounded provider/history path as Flutter.

    No arbitrary URL, SQL, account data, trade action or provider refresh option
    can be selected by the model. Never bypass Phase 1's free-tier quota guard.
    """

    def __init__(self, db: Session, market: MarketDataService, display_currency: str) -> None:
        self.db = db
        self.market = market
        self.display_currency = display_currency.upper()
        self._quotes: dict[str, dict] = {}

    async def _quote(self, symbol: str) -> dict:
        if symbol not in self._quotes:
            batch = await quotes(symbols=[symbol], force_refresh=False, service=self.market, db=self.db)
            found = next((item for item in batch.quotes if item.symbol == symbol), None)
            self._quotes[symbol] = found.model_dump(mode="json") if found else {"status": "unavailable", "asset": symbol}
        return self._quotes[symbol]

    async def _display(self, price: float, currency: str) -> dict:
        result = await self._converted_display(price, currency)
        return {**result, **currency_labels(result["currency"])}

    async def _converted_display(self, price: float, currency: str) -> dict:
        selected = self.display_currency
        if selected not in {"IRT", "USD"} or currency == selected:
            return {"price": price, "currency": currency}
        if selected == "IRT" and currency == "IRR":
            return {"price": price / 10, "currency": "IRT", "conversion_basis": "10 Rial = 1 Toman"}
        # Match CurrencyService: distinguish domestic USD from the USDT market.
        usd = await self._quote("USD")
        if usd.get("currency") != "IRT" or not self._usable(usd):
            return {"price": price, "currency": currency, "conversion_status": "unavailable"}
        rate = float(usd["price"])
        amount = price / 10 if currency == "IRR" else price
        source = "IRT" if currency == "IRR" else currency
        conversion_sources = [usd]
        if source == "USDT":
            tether = await self._quote("USDT")
            if tether.get("currency") != "IRT" or not self._usable(tether):
                return {"price": price, "currency": currency, "conversion_status": "unavailable"}
            amount *= float(tether["price"])
            source = "IRT"
            conversion_sources.append(tether)
        if source == "IRT":
            amount = amount / rate if selected == "USD" else amount
        elif source == "USD":
            amount = amount * rate if selected == "IRT" else amount
        else:
            return {"price": price, "currency": currency, "conversion_status": "unavailable"}
        return {"price": amount, "currency": selected,
                "conversion_status": "stale" if any(q.get("freshness_status") not in {"LIVE", "FRESH"} for q in conversion_sources) else "fresh",
                "conversion_basis": "latest sourced rate, not a historical exchange rate",
                "conversion_sources": [{k: q.get(k) for k in ("symbol", "price", "currency", "provider", "provider_timestamp", "freshness_status")} for q in conversion_sources]}

    @staticmethod
    def _usable(quote: dict) -> bool:
        metadata = expected_metadata(str(quote.get("symbol", "")))
        if metadata is None or quote.get("currency") not in allowed_currencies(str(quote.get("symbol", ""))):
            return False
        if quote.get("unit") != metadata[0] or quote.get("market") != metadata[2] or validate_price(quote.get("price")) is None:
            return False
        return (isinstance(quote.get("price"), (float, int)) and quote["price"] > 0
                and quote.get("data_quality_status") == "VALID"
                and quote.get("unit") not in {None, "unknown"})

    async def execute(self, name: str, arguments: dict) -> dict:
        if name == "get_assets" and not arguments:
            return {"assets": [{"symbol": a.symbol, "name": a.name} for a in SUPPORTED_ASSETS]}
        allowed = {"get_quote": {"asset"}, "get_history": {"asset", "window"}, "get_latest_forecast": {"asset"}}
        if name not in allowed or set(arguments) != allowed[name]:
            return {"status": "unavailable", "reason": "invalid_tool_arguments"}
        if not isinstance(arguments.get("asset"), str):
            return {"status": "unavailable", "reason": "invalid_asset"}
        symbol = arguments["asset"].strip().upper()
        # Models sometimes use the official display name instead of the wire
        # symbol. Normalize exact known names, not arbitrary lookalike assets.
        aliases = {item.name.upper(): item.symbol for item in SUPPORTED_ASSETS}
        aliases.update({"BITCOIN": "BTC", "TETHER": "USDT", "بیت‌کوین": "BTC", "بیت کوین": "BTC", "بیتکوین": "BTC",
                        "تتر": "USDT", "دلار آمریکا": "USD", "دلار امریکا": "USD", "یورو": "EUR",
                        "طلای ۱۸ عیار": "GOLD18", "طلای 18 عیار": "GOLD18", "اونس جهانی طلا": "XAU"})
        normalized = re.sub(r"[\s\u200c_-]", "", symbol)
        symbol = next((value for key, value in aliases.items() if re.sub(r"[\s\u200c_-]", "", key) == normalized), symbol)
        if symbol not in {a.symbol for a in SUPPORTED_ASSETS}:
            return {"status": "unavailable", "reason": "asset_not_tracked", "asset": symbol[:24]}
        if name == "get_latest_forecast":
            # Connect to the Phase 6 implementation only once its output has
            # passed that phase's acceptance gate. Do not generate a new model.
            return {"status": "unavailable", "asset": symbol, "reason": "phase_6_not_implemented",
                    "message": "No validated Phase 6 forecast is available. Do not supply a target or confidence."}
        try:
            if name == "get_quote":
                quote = await self._quote(symbol)
                if not self._usable(quote):
                    return {"status": "unavailable", "asset": symbol, "reason": "no_valid_price"}
                quote = {**quote, **currency_labels(quote["currency"])}
                observed = datetime.fromisoformat(str(quote.get("provider_timestamp") or quote["updated_at"]).replace("Z", "+00:00"))
                age = max(0, int((datetime.now(timezone.utc) - utc(observed)).total_seconds()))
                return {"status": "available", "quote": quote, "age_seconds": age,
                        "display": await self._display(float(quote["price"]), quote["currency"]),
                        "notice": "Reference quote only. Report freshness and timestamp; stale/delayed values are not live."}
            window = arguments["window"]
            if window not in {"24h", "7d", "30d"}:
                return {"status": "unavailable", "reason": "invalid_window"}
            if window == "24h" and symbol in {"USD", "EUR", "GOLD18"}:
                series = await asset_price_samples(asset=symbol, range=window, db=self.db, market_data=self.market)
                points = [item.model_dump(mode="json") for item in series.samples][-100:]
                kind = "price_samples_not_ohlc"
            else:
                # Match the app chart: prefer actual hourly venue candles;
                # domestic daily coverage is the existing fallback for 7d/30d.
                series_candles = await asset_candles(asset=symbol, timeframe="1h",
                                                     limit=750 if window == "30d" else 200 if window == "7d" else 30,
                                                     provider=None, currency=None, before=None,
                                                     db=self.db, market_data=self.market)
                cutoff = datetime.now(timezone.utc) - timedelta(days={"24h": 1, "7d": 7, "30d": 30}[window])
                points = [item.model_dump(mode="json") for item in series_candles.candles
                          if cutoff <= utc(item.closed_at) <= datetime.now(timezone.utc) and item.is_complete and item.data_quality_status == "VALID"]
                if len(points) < 2 and window in {"7d", "30d"}:
                    daily = await asset_candles(asset=symbol, timeframe="1d", limit=40,
                                               provider=None, currency=None, before=None, db=self.db, market_data=self.market)
                    points = [item.model_dump(mode="json") for item in daily.candles
                              if cutoff <= utc(item.closed_at) <= datetime.now(timezone.utc) and item.is_complete and item.data_quality_status == "VALID"]
                kind = "candles"
            points = [point for point in points if self._usable({**point, "price": point.get("price", point.get("close"))})]
            if len(points) < 2:
                return {"status": "unavailable", "asset": symbol, "window": window, "reason": "insufficient_verified_history"}
            first_price = float(points[0]["price"] if "price" in points[0] else points[0]["close"])
            last_price = float(points[-1]["price"] if "price" in points[-1] else points[-1]["close"])
            summary = {"observation_count": len(points), "first_price": first_price, "last_price": last_price,
                       "observed_change_percent": (last_price / first_price - 1) * 100,
                       "minimum_price": min(float(p["price"] if "price" in p else p["low"]) for p in points),
                       "maximum_price": max(float(p["price"] if "price" in p else p["high"]) for p in points),
                       "currency": points[0]["currency"], "unit": points[0]["unit"], "provider": points[0]["provider"],
                       "first_observation": points[0].get("closed_at") or points[0].get("provider_timestamp"),
                       "last_observation": points[-1].get("closed_at") or points[-1].get("provider_timestamp"),
                       "timezone": "UTC", "calendar": "Gregorian", "dates_must_not_be_converted_without_evidence": True}
            summary.update(currency_labels(summary["currency"]))
            # Select actual observations across the entire window, including
            # both endpoints. Never interpolate or send only the last few days.
            if len(points) > 30:
                points = [points[round(index * (len(points) - 1) / 29)] for index in range(30)]
            for point in points:
                point["display"] = await self._display(float(point["price"] if "price" in point else point["close"]), point["currency"])
            return {"status": "available", "asset": symbol, "window": window, "kind": kind, "summary": summary, "points": points,
                    "notice": "Use observed timestamps and source units. Coverage can be sparse; never fill gaps or infer volume."}
        except SQLAlchemyError:
            self.db.rollback()
            return {"status": "unavailable", "asset": symbol, "reason": "data_temporarily_unavailable"}
        except (HTTPException, httpx.HTTPError, ValueError, TypeError):
            return {"status": "unavailable", "asset": symbol, "reason": "data_temporarily_unavailable"}
