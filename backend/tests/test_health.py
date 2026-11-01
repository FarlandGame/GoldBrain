from fastapi.testclient import TestClient

from app.core.config import Settings, get_settings
from app.main import app


def test_health_endpoint() -> None:
    with TestClient(app) as client:
        response = client.get("/api/v1/health")
    assert response.status_code == 200
    body = response.json()
    assert body["status"] == "ok"
    assert body["service"] == "GoldBrain API"
    assert body["version"].startswith("0.3.0")


def test_assets_include_private_alpha_targets() -> None:
    app.dependency_overrides[get_settings] = lambda: Settings(
        environment="test", private_api_key="", auto_create_tables=False
    )
    try:
        with TestClient(app) as client:
            response = client.get("/api/v1/market/assets")
    finally:
        app.dependency_overrides.pop(get_settings, None)
    assert response.status_code == 200
    assets = {item["symbol"]: item for item in response.json()["assets"]}
    symbols = set(assets)
    assert {"USD", "USDT", "GOLD18", "XAU", "XAG", "BTC", "ETH"} <= symbols
    assert all(assets[symbol]["forecast"] for symbol in {"GOLD18", "USDT", "BTC"})
