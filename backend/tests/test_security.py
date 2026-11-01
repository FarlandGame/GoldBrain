from fastapi import Depends, FastAPI
from fastapi.testclient import TestClient
import httpx
import logging
import pytest
from datetime import datetime, timezone

from app.core.config import Settings
from app.core.security import require_private_access
from app.services.market_data import MarketDataService


def test_private_key_blocks_wrong_clients() -> None:
    app = FastAPI()
    secured = require_private_access

    @app.get("/secure", dependencies=[Depends(secured)])
    def secure() -> dict[str, bool]:
        return {"ok": True}

    # Override only the settings dependency used by require_private_access.
    from app.core.config import get_settings

    app.dependency_overrides[get_settings] = lambda: Settings(
        environment="staging", private_api_key="correct-secret", auto_create_tables=False
    )
    client = TestClient(app)
    assert client.get("/secure").status_code == 401
    assert client.get("/secure", headers={"X-GoldBrain-Key": "wrong"}).status_code == 401
    assert client.get("/secure", headers={"X-GoldBrain-Key": "correct-secret"}).status_code == 200


@pytest.mark.asyncio
async def test_query_authenticated_provider_never_logs_its_key(monkeypatch, caplog) -> None:
    # Reproduce the INFO-level httpx configuration that wrote old Worker URLs.
    caplog.set_level(logging.INFO)
    for name in ("httpx", "httpcore"):
        monkeypatch.setattr(logging.getLogger(name), "level", logging.INFO)
    key = "SyntheticPhase3TransportLogKey"
    now = int(datetime.now(timezone.utc).timestamp())
    async with httpx.AsyncClient(transport=httpx.MockTransport(lambda request: httpx.Response(
        200, json={"usd_sell": {"value": "234000", "timestamp": now}},
    ))) as client:
        service = MarketDataService(Settings(
            _env_file=None, environment="test", auto_create_tables=False, NAVASAN_API_KEY=key,
        ), client=client)
        quotes = await service._fetch_navasan()
        assert "USD" in quotes
    logging.getLogger("goldbrain.audit_test").info("safe audit capture is active")
    assert "safe audit capture is active" in caplog.text
    assert key not in caplog.text
    assert "api_key=" not in caplog.text
