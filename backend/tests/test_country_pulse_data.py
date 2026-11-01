import asyncio
import time
from datetime import datetime, timedelta, timezone

import httpx
from fastapi import FastAPI
from fastapi.testclient import TestClient

from app.api.dependencies import get_country_pulse_service
from app.api.routes.pulse import router
from app.core.security import require_client_access
from app.services.country_pulse_data import CountryPulseDataService


def test_country_index_uses_verified_symbol_and_news_outage_falls_back() -> None:
    now = datetime.now(timezone.utc)
    observed = [int((now - timedelta(days=25 - i * 5)).timestamp()) for i in range(6)]
    requested: list[str] = []

    def respond(request: httpx.Request) -> httpx.Response:
        requested.append(str(request.url))
        if "finance/chart" in request.url.path:
            assert request.url.path.endswith("/%5EGSPC") or request.url.path.endswith("/^GSPC")
            return httpx.Response(200, json={"chart": {"error": None, "result": [{
                "meta": {"symbol": "^GSPC", "currency": "USD"},
                "timestamp": observed,
                "indicators": {"quote": [{"close": [5000, 5010, 5020, 5030, 5040, 5050]}]},
            }]}})
        return httpx.Response(429, text="rate limited")

    async def run() -> None:
        async with httpx.AsyncClient(transport=httpx.MockTransport(respond)) as client:
            service = CountryPulseDataService(client, gdelt_min_interval_seconds=0)
            result = await service.get("usa", "30d")
            assert result["index_symbol"] == "^GSPC"
            assert result["index_status"] == "available"
            assert len(result["index_points"]) == 6
            assert result["news_status"] == "unavailable"
            assert result["news_tone"] is None
            assert await service.get("usa", "30d") is result
    asyncio.run(run())
    assert len(requested) == 2  # cache avoids extra public-provider calls


def test_slow_index_and_optional_news_run_concurrently() -> None:
    requested: list[str] = []

    async def respond(request: httpx.Request) -> httpx.Response:
        requested.append(request.url.host)
        await asyncio.sleep(0.2)
        return httpx.Response(503)

    async def run() -> None:
        async with httpx.AsyncClient(transport=httpx.MockTransport(respond)) as client:
            service = CountryPulseDataService(client, gdelt_min_interval_seconds=0)
            started = time.monotonic()
            result = await service.get("iran", "7d")
            assert time.monotonic() - started < 0.35
            assert result["index_status"] == "unavailable"
            assert result["news_status"] == "unavailable"

    asyncio.run(run())
    assert len(requested) == 2


def test_news_rate_limit_skips_optional_news_without_delaying_other_country() -> None:
    requested: list[str] = []

    def respond(request: httpx.Request) -> httpx.Response:
        requested.append(request.url.host)
        return httpx.Response(503)

    async def run() -> None:
        async with httpx.AsyncClient(transport=httpx.MockTransport(respond)) as client:
            service = CountryPulseDataService(client, gdelt_min_interval_seconds=30)
            await service.get("usa", "7d")
            started = time.monotonic()
            result = await service.get("france", "7d")
            assert time.monotonic() - started < 0.5
            assert result["news_status"] == "unavailable"

    asyncio.run(run())
    assert requested.count("api.gdeltproject.org") == 1


def test_iran_does_not_substitute_an_unverified_or_foreign_index() -> None:
    requested: list[str] = []

    def respond(request: httpx.Request) -> httpx.Response:
        requested.append(str(request.url))
        return httpx.Response(429, text="rate limited")

    async def run() -> None:
        async with httpx.AsyncClient(transport=httpx.MockTransport(respond)) as client:
            result = await CountryPulseDataService(client, gdelt_min_interval_seconds=0).get("iran", "7d")
            assert result["index_symbol"] == "TEDPIX"
            assert result["index_status"] == "unavailable"
            assert result["index_points"] == []
            assert result["news_status"] == "unavailable"
    asyncio.run(run())
    assert len(requested) == 2  # TSETMC failure and GDELT failure
    assert "GetIndexB2History/32097828799138957" in requested[0]


def test_tsetmc_daily_sessions_are_source_labelled_and_cannot_create_intraday_bars() -> None:
    now = datetime.now(timezone.utc)
    rows = [
        {"dEven": int((now - timedelta(days=day)).strftime("%Y%m%d")), "xNivInuClMresIbs": 4_000_000 + day}
        for day in range(1, 8)
    ]

    def respond(request: httpx.Request) -> httpx.Response:
        if "GetIndexB2History" in request.url.path:
            return httpx.Response(200, json={"indexB2": rows})
        return httpx.Response(429, text="rate limited")

    async def run() -> None:
        async with httpx.AsyncClient(transport=httpx.MockTransport(respond)) as client:
            service = CountryPulseDataService(client, gdelt_min_interval_seconds=0)
            weekly = await service.get("iran", "7d")
            daily = await service.get("iran", "24h")
            assert weekly["index_provider"] == "TSETMC"
            assert weekly["unit"] == "index_points"
            assert len(weekly["index_points"]) >= 4
            assert len(daily["index_points"]) <= 1
    asyncio.run(run())


def test_country_evidence_rejects_currency_mismatch_and_uses_sourced_news_tone() -> None:
    now = datetime.now(timezone.utc)
    observed = [int((now - timedelta(days=6 - day)).timestamp()) for day in range(6)]

    def respond(request: httpx.Request) -> httpx.Response:
        if "finance/chart" in request.url.path:
            return httpx.Response(200, json={"chart": {"error": None, "result": [{
                "meta": {"symbol": "^GDAXI", "currency": "USD"},
                "timestamp": observed,
                "indicators": {"quote": [{"close": [100, 101, 102, 103, 104, 105]}]},
            }]}})
        return httpx.Response(200, json={"timeline": [{"series": "Tone", "data": [
            {"value": -2.0}, {"value": 2.0}, {"value": 3.0},
        ]}]})

    async def run() -> None:
        async with httpx.AsyncClient(transport=httpx.MockTransport(respond)) as client:
            result = await CountryPulseDataService(client, gdelt_min_interval_seconds=0).get("germany", "7d")
            assert result["index_status"] == "unavailable"
            assert result["index_points"] == []
            assert result["news_status"] == "available"
            assert result["news_tone"] == 1.0
    asyncio.run(run())


def test_country_pulse_contract_returns_source_and_rejects_unknown_window() -> None:
    class StubService:
        async def get(self, country: str, window: str) -> dict:
            return {
                "country": country, "window": window, "index_symbol": "^GSPC",
                "index_name": "S&P 500", "currency": "USD", "unit": "index_points",
                "index_provider": "Yahoo Finance public chart",
                "index_source_url": "https://finance.yahoo.com/markets/world-indices/",
                "index_status": "unavailable", "index_points": [],
                "last_observation_at": None, "news_provider": "GDELT DOC 2.0",
                "news_status": "unavailable", "news_tone": None,
                "news_source_url": "https://blog.gdeltproject.org/gdelt-doc-2-0-api-debuts/",
                "checked_at": datetime.now(timezone.utc).isoformat(),
            }

    app = FastAPI()
    app.include_router(router, prefix="/api/v1")
    app.dependency_overrides[require_client_access] = lambda: None
    app.dependency_overrides[get_country_pulse_service] = StubService
    with TestClient(app) as client:
        response = client.get("/api/v1/pulse/countries/usa?window=30d")
        assert response.status_code == 200
        assert response.json()["index_symbol"] == "^GSPC"
        assert response.json()["index_points"] == []
        assert client.get("/api/v1/pulse/countries/usa?window=2d").status_code == 404
