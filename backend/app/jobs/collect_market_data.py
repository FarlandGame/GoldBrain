from __future__ import annotations

import asyncio
import json

from app.core.config import get_settings
from app.db.session import SessionLocal
from app.services.market_collector import MarketCollector
from app.services.market_data import MarketDataService


async def main() -> None:
    settings = get_settings()
    market_data = MarketDataService(settings)
    db = SessionLocal()
    try:
        result = await MarketCollector(market_data).collect_once(db)
        print(
            json.dumps(
                {
                    "requested_symbols": result.requested_symbols,
                    "collected_quotes": result.collected_quotes,
                    "issues": result.quote_issues,
                    "candles": {
                        symbol: {
                            "inserted": outcome.inserted,
                            "updated": outcome.updated,
                            "rejected": outcome.rejected,
                        }
                        for symbol, outcome in result.candles.items()
                    },
                },
                ensure_ascii=False,
            )
        )
    finally:
        db.close()
        await market_data.close()


if __name__ == "__main__":
    asyncio.run(main())
