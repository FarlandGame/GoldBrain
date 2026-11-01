from datetime import datetime, timezone

import pytest
from sqlalchemy import create_engine, select
from sqlalchemy.orm import sessionmaker

from app import models as _models  # noqa: F401
from app.db.base import Base
from app.models.market import MarketQuoteRecord
from app.schemas.market import MarketQuote
from app.services.market_collector import MarketCollector
from app.services.market_data import QuoteBatch


class FakeMarketDataService:
    async def fetch_quotes(self, symbols, force_refresh=False):
        assert force_refresh is True
        assert tuple(symbols) == ("GOLD18", "USDT", "BTC", "XAU")
        now = datetime.now(timezone.utc)
        quotes = {
            "GOLD18": MarketQuote(
                symbol="GOLD18", name="Gold", currency="IRT", price=10000000, updated_at=now, provider="test"
            ),
            "USDT": MarketQuote(
                symbol="USDT", name="Tether", currency="IRT", price=90000, updated_at=now, provider="test"
            ),
            "BTC": MarketQuote(
                symbol="BTC", name="Bitcoin", currency="USDT", price=65000, updated_at=now, provider="test"
            ),
            "XAU": MarketQuote(
                symbol="XAU", name="Gold Ounce", currency="USD", price=3000, updated_at=now, provider="test"
            ),
        }
        return QuoteBatch(requested=tuple(symbols), quotes=quotes, issues={})


@pytest.mark.asyncio
async def test_collector_persists_private_beta_quotes() -> None:
    engine = create_engine("sqlite://")
    Base.metadata.create_all(engine)
    session = sessionmaker(bind=engine)()
    try:
        result = await MarketCollector(FakeMarketDataService()).collect_once(session)
        records = list(session.scalars(select(MarketQuoteRecord)))
    finally:
        session.close()
        engine.dispose()

    assert result.collected_quotes == 4
    assert result.quote_issues == {}
    assert {record.symbol for record in records} == {"GOLD18", "USDT", "BTC", "XAU"}
