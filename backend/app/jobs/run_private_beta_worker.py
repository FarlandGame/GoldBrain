from __future__ import annotations

import asyncio
import json
import logging
import time

from app.core.config import get_settings
from app.jobs.run_private_beta_cycle import run_once

logger = logging.getLogger(__name__)


async def main() -> None:
    """Run the safe private-beta collection cycle at a bounded interval.

    This worker only collects data, aggregates honest candles, forecasts and
    evaluates outcomes. It never submits exchange orders.
    """
    settings = get_settings()
    interval = settings.market_collection_interval_seconds
    while True:
        started = time.monotonic()
        try:
            print(json.dumps(await run_once(), ensure_ascii=False), flush=True)
        except Exception:  # keep a transient provider/database error observable and recoverable
            logger.exception("Private-beta market cycle failed; retrying on the next interval.")
        await asyncio.sleep(max(1, interval - (time.monotonic() - started)))


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO)
    asyncio.run(main())
