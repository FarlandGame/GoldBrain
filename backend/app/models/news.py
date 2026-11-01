from __future__ import annotations

from datetime import datetime, timezone

from sqlalchemy import DateTime, Index, String, Text
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base


class NewsArticleRecord(Base):
    __tablename__ = "news_articles"
    __table_args__ = (Index("ix_news_published_source", "published_at", "source"),)

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    article_id: Mapped[str] = mapped_column(String(80), unique=True, index=True)
    title: Mapped[str] = mapped_column(String(1000))
    summary: Mapped[str] = mapped_column(Text, default="")
    source: Mapped[str] = mapped_column(String(120), index=True)
    category: Mapped[str] = mapped_column(String(80), default="economy")
    language: Mapped[str] = mapped_column(String(20), default="persian")
    url: Mapped[str] = mapped_column(String(1200))
    published_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), index=True)
    fetched_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc)
    )
