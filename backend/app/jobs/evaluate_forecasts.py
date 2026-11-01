from __future__ import annotations

import json

from app.db.session import SessionLocal
from app.services.forecasting import ForecastService


def main() -> None:
    db = SessionLocal()
    try:
        evaluated, expired, pending = ForecastService().evaluate_due(db)
        print(json.dumps({"evaluated": evaluated, "expired": expired, "pending": pending}))
    finally:
        db.close()


if __name__ == "__main__":
    main()
