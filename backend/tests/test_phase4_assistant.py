from __future__ import annotations

import asyncio
import json
from datetime import datetime, timedelta, timezone

import httpx
import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import Session
from sqlalchemy.pool import StaticPool

from app.api.dependencies import get_identity, get_market_service
from app.api.routes.assistant import get_assistant_service
from app.core.config import Settings
from app.db.base import Base
from app.db.session import get_db
from app.models.candle import MarketCandleRecord
from app.main import create_app
from app.schemas.assistant import AssistantRequest
from app.schemas.market import MarketQuote
from app.api.assistant_tools import AssistantDataTools
from app.services.assistant import AssistantError, AssistantService, language_matches
from app.services.history import MarketHistoryService
from app.services.market_data import QuoteBatch


def _settings(**kwargs):
    return Settings(environment="test", GAPGPT_API_KEY="synthetic-phase4-key", GAPGPT_BASE_URL="https://openrouter.ai/api/v1", GAPGPT_MODEL="openrouter/free", **kwargs)


def _reply(text="این پاسخ از داده‌های واقعی برنامه ساخته شده است.", calls=None):
    return httpx.Response(200, json={"model": "synthetic/model:free", "choices": [{"message": {"role": "assistant", "content": text, "tool_calls": calls}}]})


def _call(name="get_quote", arguments=None, call_id="one"):
    return {"id": call_id, "type": "function", "function": {"name": name, "arguments": json.dumps(arguments or {"asset": "BTC"})}}


async def _execute(name, arguments):
    return {"status": "unavailable", "tool": name, "asset": arguments.get("asset")}


@pytest.mark.parametrize("tone,temperature,marker", [("concise", 0.1, "concise"), ("detailed", 0.8, "detailed"), ("balanced", 0.35, "Balance brevity")])
def test_settings_affect_the_real_provider_payload(tone, temperature, marker):
    captured = []

    def transport(request):
        captured.append(json.loads(request.content))
        return _reply()

    async def run():
        async with httpx.AsyncClient(transport=httpx.MockTransport(transport)) as client:
            result = await AssistantService(_settings(), client).chat(AssistantRequest(messages=[{"role": "user", "content": "سلام"}], tone=tone, temperature=temperature), _execute)
            assert result.text.startswith("این")
    asyncio.run(run())
    assert captured[0]["temperature"] == temperature
    assert marker in captured[0]["messages"][0]["content"]
    assert "short, friendly, conversational answer" in captured[0]["messages"][0]["content"]
    assert "A simple price question needs two or three sentences" in captured[0]["messages"][0]["content"]
    assert "not a technical report" in captured[0]["messages"][0]["content"]
    assert "do not ask them to choose it again" in captured[0]["messages"][0]["content"]
    assert "IRT always means Toman" in captured[0]["messages"][0]["content"]
    assert captured[0]["model"] == "openrouter/free" and captured[0]["max_tokens"] == 2000
    assert captured[0]["reasoning"] == {"effort": "low", "exclude": True}


def test_tool_loop_requires_evidence_and_deduplicates_data_calls():
    requests = []
    executed = []

    def transport(request):
        body = json.loads(request.content)
        requests.append(body)
        if len(requests) == 1:
            return _reply(None, [_call(), _call(call_id="two")])
        return _reply()

    async def execute(name, arguments):
        executed.append((name, arguments))
        return {"status": "available", "quote": {"price": 42, "currency": "USDT", "freshness_status": "STALE", "provider": "synthetic-market"}}

    async def run():
        async with httpx.AsyncClient(transport=httpx.MockTransport(transport)) as client:
            response = await AssistantService(_settings(), client).chat(AssistantRequest(messages=[{"role": "user", "content": "قیمت BTC"}]), execute)
            assert len(response.evidence) == 1
            assert response.evidence[0].data["quote"]["freshness_status"] == "STALE"
    asyncio.run(run())
    assert len(executed) == 1
    assert requests[0]["tool_choice"] == "required"
    assert len([m for m in requests[1]["messages"] if m["role"] == "tool"]) == 2


@pytest.mark.parametrize("failure,expected", [(429, "assistant_rate_limited"), (403, "assistant_unavailable"), (503, "assistant_unavailable"), ("timeout", "assistant_timeout"), ("invalid", "assistant_unavailable")])
def test_upstream_failures_never_echo_credentials(failure, expected, caplog):
    def transport(request):
        if failure == "timeout":
            raise httpx.ReadTimeout("synthetic-phase4-key", request=request)
        if failure == "invalid":
            return httpx.Response(200, text="synthetic-phase4-key")
        return httpx.Response(failure, json={"error": "synthetic-phase4-key"})

    async def run():
        async with httpx.AsyncClient(transport=httpx.MockTransport(transport)) as client:
            with pytest.raises(AssistantError) as caught:
                await AssistantService(_settings(), client).chat(AssistantRequest(messages=[{"role": "user", "content": "سلام"}]), _execute)
            assert caught.value.code == expected
            assert "synthetic-phase4-key" not in str(caught.value)
    asyncio.run(run())
    assert "synthetic-phase4-key" not in caplog.text


def test_context_and_secret_redaction_are_bounded():
    captured = []

    def transport(request):
        captured.append(json.loads(request.content))
        return _reply("این پاسخ synthetic-phase4-key نباید کلید داشته باشد.")

    async def run():
        async with httpx.AsyncClient(transport=httpx.MockTransport(transport)) as client:
            messages = [{"role": "user", "content": str(i) + "z" * 3990} for i in range(23)] + [{"role": "user", "content": "synthetic-phase4-key"}]
            result = await AssistantService(_settings(), client).chat(AssistantRequest(messages=messages, market_context=False), _execute)
            assert result.history_trimmed
            assert "synthetic-phase4-key" not in result.text
    asyncio.run(run())
    history = captured[0]["messages"][1:]
    assert len(history) <= 12 and sum(len(item["content"]) for item in history) <= 12000
    assert "synthetic-phase4-key" not in json.dumps(captured)
    assert "tools" not in captured[0]


def test_language_repair_is_bounded_and_keeps_tool_evidence():
    captured = []

    def transport(request):
        captured.append(json.loads(request.content))
        return _reply("This is a response entirely in English." if len(captured) == 1 else "این پاسخ با حفظ واقعیت‌ها به فارسی نوشته شده است.")

    async def run():
        async with httpx.AsyncClient(transport=httpx.MockTransport(transport)) as client:
            result = await AssistantService(_settings(), client).chat(AssistantRequest(messages=[{"role": "user", "content": "سلام"}]), _execute)
            assert language_matches(result.text, "persian")
    asyncio.run(run())
    assert len(captured) == 2 and captured[1]["temperature"] == 0
    assert "tools" not in captured[1]


@pytest.mark.parametrize("question,repair_needed", [("قیمت BTC چنده؟", True), ("قیمت BTC را در جدول با جزئیات بگو", False)])
def test_simple_price_reports_get_one_fact_preserving_style_repair(question, repair_needed):
    captured = []

    def transport(request):
        captured.append(json.loads(request.content))
        if len(captured) == 1:
            return _reply(None, [_call()])
        if len(captured) == 2:
            return _reply("- **قیمت:** 42 USDT\n- وضعیت: DELAYED؛ قیمت با تأخیر است.")
        return _reply("آخرین قیمت ثبت‌شده 42 USDT است؛ این داده با تأخیر رسیده و لحظه‌ای نیست.")

    async def execute(name, arguments):
        return {"status": "available", "quote": {"price": 42, "currency": "USDT", "freshness_status": "DELAYED"}}

    async def run():
        async with httpx.AsyncClient(transport=httpx.MockTransport(transport)) as client:
            result = await AssistantService(_settings(), client).chat(AssistantRequest(messages=[{"role": "user", "content": question}]), execute)
            assert result.evidence[0].data["quote"]["price"] == 42
            assert "42 USDT" in result.text
            if repair_needed:
                assert "DELAYED" not in result.text and not result.text.startswith("-")
    asyncio.run(run())
    assert len(captured) == (3 if repair_needed else 2)
    if repair_needed:
        assert "tools" not in captured[-1] and captured[-1]["temperature"] == 0
        assert "Preserve its facts, prices" in captured[-1]["messages"][-1]["content"]
        assert "two or three short, friendly" in captured[-1]["messages"][-1]["content"]


def test_conversational_price_answer_does_not_consume_a_style_retry():
    calls = []

    def transport(request):
        calls.append(request)
        return _reply(None, [_call()]) if len(calls) == 1 else _reply("آخرین قیمت 42 USDT است؛ با تأخیر رسیده و لحظه‌ای نیست.")

    async def run():
        async with httpx.AsyncClient(transport=httpx.MockTransport(transport)) as client:
            await AssistantService(_settings(), client).chat(AssistantRequest(messages=[{"role": "user", "content": "قیمت BTC"}]), _execute)
    asyncio.run(run())
    assert len(calls) == 2


@pytest.mark.parametrize("currency,status", [("USD", "stale"), ("IRT", "stale"), ("USD", "available")])
def test_converted_quote_cannot_silently_lose_its_stale_fx_disclosure(currency, status):
    calls = []

    def transport(request):
        calls.append(request)
        return _reply(None, [_call()]) if len(calls) == 1 else _reply("آخرین قیمت ثبت‌شده حدود 105 است؛ قیمت با تأخیر رسیده است.")

    async def execute(name, arguments):
        return {"status": "available", "quote": {"price": 100, "currency": "USDT"},
                "display": {"price": 105, "currency": currency, "conversion_status": status}}

    async def run():
        async with httpx.AsyncClient(transport=httpx.MockTransport(transport)) as client:
            result = await AssistantService(_settings(), client).chat(AssistantRequest(
                messages=[{"role": "user", "content": "قیمت BTC چنده؟"}], display_currency=currency), execute)
            assert ("نرخ ارزِ این تبدیل قدیمی است" in result.text) == (status == "stale")
            assert "105" in result.text and result.evidence[0].data["display"]["price"] == 105
    asyncio.run(run())
    assert len(calls) == 2


def test_openrouter_paid_model_is_blocked_before_network():
    settings = _settings()
    settings.ai_model = "paid/model"
    async def run():
        async with httpx.AsyncClient(transport=httpx.MockTransport(lambda _: pytest.fail("No paid request allowed"))) as client:
            with pytest.raises(AssistantError, match="assistant_free_model_required"):
                await AssistantService(settings, client).chat(AssistantRequest(messages=[{"role": "user", "content": "Hi"}]), _execute)
    asyncio.run(run())


def test_tool_loop_cannot_run_forever():
    requests = []
    def transport(request):
        requests.append(request)
        return _reply(None, [_call()])
    async def run():
        async with httpx.AsyncClient(transport=httpx.MockTransport(transport)) as client:
            with pytest.raises(AssistantError, match="assistant_tool_limit"):
                await AssistantService(_settings(), client).chat(AssistantRequest(messages=[{"role": "user", "content": "قیمت طلا"}]), _execute)
    asyncio.run(run())
    assert len(requests) == 4


class FakeMarket:
    def __init__(self, down=False):
        self.down = down
        self.force_refresh = []

    async def fetch_quotes(self, symbols, force_refresh=False):
        self.force_refresh.append(force_refresh)
        now = datetime.now(timezone.utc)
        values = {"BTC": (100.0, "USDT"), "USD": (200000.0, "IRT"), "USDT": (210000.0, "IRT"), "GOLD18": (24000000.0, "IRT")}
        return QuoteBatch(requested=tuple(symbols), quotes={} if self.down else {
            symbol: MarketQuote(symbol=symbol, name=symbol, price=values[symbol][0], currency=values[symbol][1], updated_at=now - timedelta(hours=3), provider="synthetic-provider", unit="gram_18k" if symbol == "GOLD18" else "currency_unit" if symbol == "USD" else "coin", market="GLOBAL" if symbol == "BTC" else "IRAN", provider_timestamp=now - timedelta(hours=3), received_at=now, freshness_status="STALE", data_quality_status="VALID") for symbol in symbols
        }, issues={})

    def drain_observability(self):
        return []


@pytest.fixture
def db():
    engine = create_engine("sqlite://", connect_args={"check_same_thread": False}, poolclass=StaticPool)
    Base.metadata.create_all(engine)
    with Session(engine) as session:
        yield session
    engine.dispose()


@pytest.mark.parametrize("currency,expected", [("USD", 105.0), ("IRT", 21000000.0)])
def test_quote_conversion_uses_sourced_fx_not_usdt_parity(db, currency, expected):
    market = FakeMarket()
    result = asyncio.run(AssistantDataTools(db, market, currency).execute("get_quote", {"asset": "BTC"}))
    assert result["quote"]["price"] == 100
    assert result["quote"]["currency"] == "USDT"
    assert result["quote"]["freshness_status"] == "STALE"
    assert result["display"]["currency"] == currency and result["display"]["price"] == expected
    assert result["display"]["currency_name_fa"] == ("تومان" if currency == "IRT" else "دلار آمریکا")
    assert result["quote"]["currency_name"] == "Tether"
    assert result["display"]["conversion_status"] == "stale"
    assert result["age_seconds"] >= 10800
    assert not any(market.force_refresh)


def test_provider_down_keeps_visible_last_known_source(db):
    async def run():
        normal = FakeMarket()
        quote = (await normal.fetch_quotes(["BTC"])).quotes["BTC"]
        MarketHistoryService().persist_quotes(db, [quote])
        result = await AssistantDataTools(db, FakeMarket(down=True), "auto").execute("get_quote", {"asset": "BTC"})
        assert result["quote"]["provider"] == "synthetic-provider"
        assert result["quote"]["freshness_status"] == "STALE"
    asyncio.run(run())


@pytest.mark.parametrize("name,args,reason", [
    ("get_quote", {"asset": "NOCOIN"}, "asset_not_tracked"),
    ("get_latest_forecast", {"asset": "BTC"}, "phase_6_not_implemented"),
    ("delete_account", {"asset": "BTC"}, "invalid_tool_arguments"),
    ("get_quote", {"asset": "BTC", "url": "https://untrusted.invalid"}, "invalid_tool_arguments"),
])
def test_unavailable_assets_predictions_and_write_tools_are_honest(db, name, args, reason):
    result = asyncio.run(AssistantDataTools(db, FakeMarket(), "IRT").execute(name, args))
    assert result["status"] == "unavailable" and result["reason"] == reason
    assert "price" not in result and "confidence" not in result


def test_real_route_auth_validation_and_sanitized_failure(db):
    test_app = create_app()
    test_app.dependency_overrides[get_db] = lambda: db
    test_app.dependency_overrides[get_market_service] = lambda: FakeMarket()
    class FailedAssistant:
        async def chat(self, *args):
            raise AssistantError("assistant_rate_limited", 429)
    test_app.dependency_overrides[get_assistant_service] = lambda: FailedAssistant()
    with TestClient(test_app) as client:
        payload = {"messages": [{"role": "user", "content": "Hi"}]}
        assert client.post("/api/v1/assistant/chat", json=payload).status_code == 401
        test_app.dependency_overrides[get_identity] = lambda: object()
        response = client.post("/api/v1/assistant/chat", json=payload)
        assert response.status_code == 429
        assert response.json()["error"]["code"] == "assistant_rate_limited"
        invalid = client.post("/api/v1/assistant/chat", json={**payload, "api_key": "synthetic-private-value"})
        assert invalid.status_code == 422 and "synthetic-private-value" not in invalid.text
        assert client.get("/openapi.json").status_code == 200


def test_history_uses_real_stored_closes_and_does_not_fill_gaps(db):
    now = datetime.now(timezone.utc).replace(hour=0, minute=0, second=0, microsecond=0)
    for days in (6, 4, 1):
        db.add(MarketCandleRecord(symbol="BTC", timeframe="1d", currency="USDT", provider="synthetic-history",
            opened_at=now - timedelta(days=days), closed_at=now - timedelta(days=days - 1),
            open=100, high=110, low=90, close=100 + days, unit="coin", market="GLOBAL",
            data_quality_status="VALID", freshness_status="STALE", is_complete=True, source_tick_ids=[]))
    # Legacy bad rows must not become model evidence even if they exist in DB.
    db.add(MarketCandleRecord(symbol="BTC", timeframe="1d", currency="USDT", provider="synthetic-history",
        opened_at=now - timedelta(days=3), closed_at=now - timedelta(days=2),
        open=100, high=110, low=90, close=105, unit="gram_18k", market="GLOBAL",
        data_quality_status="VALID", is_complete=True, source_tick_ids=[]))
    db.commit()
    result = asyncio.run(AssistantDataTools(db, FakeMarket(), "auto").execute("get_history", {"asset": "BTC", "window": "7d"}))
    assert result["status"] == "available"
    assert [point["close"] for point in result["points"]] == [106, 104, 101]
    assert len(result["points"]) == 3 and all(p["provider"] == "synthetic-history" for p in result["points"])
    assert result["summary"]["minimum_price"] == 90
    assert result["summary"]["maximum_price"] == 110
    assert result["summary"]["observed_change_percent"] == pytest.approx((101 / 106 - 1) * 100)
    assert result["summary"]["timezone"] == "UTC" and result["summary"]["calendar"] == "Gregorian"
    assert all(p["display"]["currency"] == "USDT" for p in result["points"])
    assert all(p["display"]["currency_name_fa"] == "تتر" for p in result["points"])


@pytest.mark.parametrize("source,target,price,expected,label", [
    ("IRR", "IRT", 1000, 100, "تومان"),
    ("IRT", "IRT", 1000, 1000, "تومان"),
    ("USD", "USD", 100, 100, "دلار آمریکا"),
    ("USDT", "auto", 100, 100, "تتر"),
])
def test_display_amount_and_explicit_unit_label_are_consistent(db, source, target, price, expected, label):
    result = asyncio.run(AssistantDataTools(db, FakeMarket(), target)._display(price, source))
    assert result["price"] == expected
    assert result["currency_name_fa"] == label


@pytest.mark.parametrize("body", [
    {"choices": []}, {"choices": [{"message": "bad"}]},
    {"choices": [{"message": {"content": "truncated"}, "finish_reason": "length"}]},
    {"choices": [{"message": {"tool_calls": ["bad"]}}]},
])
def test_malformed_upstream_payload_is_a_safe_error(body):
    async def run():
        async with httpx.AsyncClient(transport=httpx.MockTransport(lambda _: httpx.Response(200, json=body))) as client:
            with pytest.raises(AssistantError, match="assistant_invalid_response"):
                await AssistantService(_settings(), client).chat(AssistantRequest(messages=[{"role": "user", "content": "Hi"}]), _execute)
    asyncio.run(run())


@pytest.mark.parametrize("name,symbol", [("Bitcoin", "BTC"), ("بیت‌کوین", "BTC"), ("بیت کوین", "BTC"), ("طلای ۱۸ عیار", "GOLD18"), ("Tether", "USDT")])
def test_exact_display_names_resolve_without_substituting_assets(db, name, symbol):
    result = asyncio.run(AssistantDataTools(db, FakeMarket(), "auto").execute("get_latest_forecast", {"asset": name}))
    assert result["asset"] == symbol
    assert result["reason"] == "phase_6_not_implemented"
