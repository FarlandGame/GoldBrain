from __future__ import annotations

import argparse
import asyncio
import json
from datetime import datetime, timedelta, timezone

from app.core.config import get_settings
from app.db.session import SessionLocal
from app.services.history import MarketHistoryService
from app.services.market_data import MarketDataService


def lookback_hours(value: str) -> int:
    try:
        parsed = int(value)
    except ValueError as exc:
        raise argparse.ArgumentTypeError("lookback hours must be an integer") from exc
    if not 1 <= parsed <= 2160:
        raise argparse.ArgumentTypeError("lookback hours must be between 1 and 2160")
    return parsed


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Backfill public Wallex BTC/USDT OHLCV history.")
    parser.add_argument("--symbol", required=True, choices=("BTC", "USDT"))
    parser.add_argument("--timeframe", default="1h", choices=("1m", "1h", "1d"))
    parser.add_argument("--lookback-hours", type=lookback_hours, default=720, metavar="HOURS")
    return parser.parse_args()


async def main() -> None:
    args = parse_args()
    settings = get_settings()
    market_data = MarketDataService(settings)
    db = SessionLocal()
    try:
        end_at = datetime.now(timezone.utc)
        candles = await market_data.fetch_wallex_candles(
            symbol=args.symbol,
            timeframe=args.timeframe,
            start_at=end_at - timedelta(hours=args.lookback_hours),
            end_at=end_at,
        )
        result = MarketHistoryService().upsert_candles(db, candles)
        print(
            json.dumps(
                {
                    "symbol": args.symbol,
                    "timeframe": args.timeframe,
                    "fetched": len(candles),
                    "inserted": result.inserted,
                    "updated": result.updated,
                    "rejected": result.rejected,
                },
                ensure_ascii=False,
            )
        )
    finally:
        db.close()
        await market_data.close()


if __name__ == "__main__":
    asyncio.run(main())
