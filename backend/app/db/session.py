from __future__ import annotations

from collections.abc import Generator

from sqlalchemy import create_engine
from sqlalchemy.orm import Session, sessionmaker

from app.core.config import get_settings

settings = get_settings()
_is_sqlite = settings.database_url.startswith("sqlite")
_connect_args = {"check_same_thread": False} if _is_sqlite else {}
_engine_options: dict[str, object] = {"pool_pre_ping": True, "connect_args": _connect_args}
if not _is_sqlite:
    _engine_options.update({"pool_size": 10, "max_overflow": 20, "pool_recycle": 1800})
engine = create_engine(settings.database_url, **_engine_options)
SessionLocal = sessionmaker(bind=engine, autoflush=False, autocommit=False, expire_on_commit=False)


def get_db() -> Generator[Session, None, None]:
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
