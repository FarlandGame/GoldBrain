from __future__ import annotations

import asyncio
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from difflib import SequenceMatcher
import hashlib
from html import unescape
import re
from urllib.parse import parse_qsl, urlencode, urlparse, urlunparse
import xml.etree.ElementTree as ET

import httpx
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models.news import NewsArticleRecord
from app.schemas.intelligence import NewsArticle, NewsResponse
from app.services.market_data import SUPPORTED_ASSETS


@dataclass(frozen=True)
class FeedSource:
    name: str
    url: str
    allowed_hosts: frozenset[str]
    category: str
    language: str = "persian"


DEFAULT_FEEDS = (
    FeedSource(
        name="Tasnim News Agency — Economy",
        url="https://www.tasnimnews.ir/fa/rss/feeds/7/0/0/0",
        allowed_hosts=frozenset({"tasnimnews.ir", "www.tasnimnews.ir"}),
        category="economy",
    ),
    FeedSource(
        name="Mehr News Agency — Economy",
        url="https://www.mehrnews.com/rss/tp/25",
        allowed_hosts=frozenset({"mehrnews.com", "www.mehrnews.com"}),
        category="economy",
    ),
    FeedSource(
        name="Mehr News Agency — Gold & Coin",
        url="https://www.mehrnews.com/rss/tp/672",
        allowed_hosts=frozenset({"mehrnews.com", "www.mehrnews.com"}),
        category="gold",
    ),
    FeedSource(
        name="Cointelegraph",
        url="https://cointelegraph.com/rss",
        allowed_hosts=frozenset({"cointelegraph.com", "www.cointelegraph.com"}),
        category="crypto",
        language="english",
    ),
    FeedSource(
        name="CNBC — Finance",
        url="https://www.cnbc.com/id/10000664/device/rss/rss.html",
        allowed_hosts=frozenset({"cnbc.com", "www.cnbc.com"}),
        category="finance",
        language="english",
    ),
)


class NewsService:
    POLL_INTERVAL = timedelta(minutes=5)
    MAX_BYTES = 2 * 1024 * 1024

    def __init__(self, client: httpx.AsyncClient | None = None, *,
                 sources: tuple[FeedSource, ...] = DEFAULT_FEEDS,
                 clock=None) -> None:
        self._owns_client = client is None
        self.client = client or httpx.AsyncClient(
            timeout=httpx.Timeout(12.0),
            headers={"accept": "application/rss+xml, application/xml, text/xml", "user-agent": "GoldBrain/0.2"},
            follow_redirects=False,
        )
        self.sources = sources
        self._clock = clock or (lambda: datetime.now(timezone.utc))
        self._lock = asyncio.Lock()
        self._checked_at: datetime | None = None
        self._errors: dict[str, str] = {}
        self._validators: dict[str, dict[str, str]] = {}
        self._source_cache: dict[str, list[NewsArticle]] = {}

    async def close(self) -> None:
        if self._owns_client:
            await self.client.aclose()

    async def refresh(self, db: Session) -> NewsResponse:
        # Shared service serializes refreshes; manual refresh respects the same
        # source cadence. Independent feeds run concurrently, never fail as a unit.
        async with self._lock:
            now = _utc(self._clock())
            if self._checked_at is not None and now - self._checked_at < self.POLL_INTERVAL:
                return self._snapshot(db, from_cache=True)
            results = await asyncio.gather(*(self._fetch(source) for source in self.sources), return_exceptions=True)
            errors: dict[str, str] = {}
            received = _utc(self._clock())
            succeeded = False
            try:
                seen_ids: set[str] = set()
                for source, result in zip(self.sources, results, strict=True):
                    if isinstance(result, BaseException):
                        errors[source.name] = "News source is temporarily unavailable; last-known articles may be shown."
                        continue
                    succeeded = True
                    for article in result:
                        # Production SessionLocal disables autoflush. A second
                        # feed can repeat an as-yet unflushed URL in this batch.
                        if article.article_id in seen_ids:
                            continue
                        seen_ids.add(article.article_id)
                        existing = db.scalar(select(NewsArticleRecord).where(NewsArticleRecord.article_id == article.article_id))
                        if existing is None:
                            db.add(NewsArticleRecord(
                                article_id=article.article_id, title=article.title, summary=article.summary,
                                source=article.source, category=article.category, language=article.language,
                                url=article.url, published_at=article.published_at, fetched_at=received,
                            ))
                        else:
                            # Publisher corrections remain traceable to the URL;
                            # a failed source never overwrites its valid stored text.
                            existing.title, existing.summary = article.title, article.summary
                            existing.published_at, existing.fetched_at = article.published_at, received
                db.commit()
            except Exception:
                db.rollback()
                raise
            self._errors, self._checked_at = errors, received
            return self._snapshot(db, from_cache=not succeeded)

    def latest(self, db: Session, *, limit: int = 60) -> list[NewsArticle]:
        rows = list(db.scalars(select(NewsArticleRecord).order_by(NewsArticleRecord.published_at.desc()).limit(300)))
        # Rank recent items only; a week-old relevant story must not crowd out
        # current news. Retain older records in DB for provenance.
        cutoff = _utc(self._clock()) - timedelta(days=7)
        articles = [self._schema(row) for row in rows if _utc(row.published_at) >= cutoff]
        return rank_and_deduplicate(articles)[:limit]

    def _snapshot(self, db: Session, *, from_cache: bool) -> NewsResponse:
        articles = self.latest(db)
        fetched = max((item.fetched_at for item in articles if item.fetched_at is not None), default=datetime(1970, 1, 1, tzinfo=timezone.utc))
        return NewsResponse(articles=articles, source_errors=self._errors, fetched_at=fetched, from_cache=from_cache)

    async def _fetch(self, source: FeedSource) -> list[NewsArticle]:
        async with self.client.stream("GET", source.url, headers=self._validators.get(source.name, {})) as response:
            if response.status_code == 304 and source.name in self._source_cache:
                return self._source_cache[source.name]
            if not 200 <= response.status_code < 300:
                raise ValueError("invalid feed response")
            payload = bytearray()
            async for chunk in response.aiter_bytes():
                payload.extend(chunk)
                if len(payload) > self.MAX_BYTES:
                    raise ValueError("feed too large")
            if b"<!DOCTYPE" in payload.upper() or b"<!ENTITY" in payload.upper():
                raise ValueError("unsafe XML")
            root = ET.fromstring(payload)
            validators = {}
            for header, request_header in (("etag", "If-None-Match"), ("last-modified", "If-Modified-Since")):
                if response.headers.get(header):
                    validators[request_header] = response.headers[header]
        output: list[NewsArticle] = []
        for item in root.findall(".//item")[:12]:
            title = _text(item.findtext("title"), 1000)
            link = _canonical_url(_text(item.findtext("link"), 1200))
            summary = _text(item.findtext("description"), 5000)
            published = _parse_date(item.findtext("pubDate"))
            parsed = urlparse(link)
            host = (parsed.hostname or "").lower()
            if (not title or parsed.scheme not in {"http", "https"} or parsed.username or parsed.password
                    or host not in source.allowed_hosts or published is None
                    or published > _utc(self._clock()) + timedelta(minutes=5)):
                continue
            article_id = hashlib.sha256(link.encode()).hexdigest()
            output.append(
                NewsArticle(
                    article_id=article_id,
                    title=title,
                    summary=summary,
                    source=source.name,
                    category=source.category,
                    language=source.language,
                    url=link,
                    published_at=published,
                )
            )
        if not output:
            raise ValueError("no valid news items")
        self._validators[source.name] = validators
        self._source_cache[source.name] = output
        return output

    def _schema(self, row: NewsArticleRecord) -> NewsArticle:
        source = next((s for s in self.sources if s.name == row.source), None)
        article = NewsArticle(
            article_id=row.article_id,
            title=row.title,
            summary=row.summary,
            source=row.source,
            category=row.category,
            language=row.language,
            url=row.url,
            published_at=_utc(row.published_at),
            fetched_at=_utc(row.fetched_at),
            source_information_url=source.url if source else None,
        )
        assets, score = relevance(article)
        return article.model_copy(update={"relevant_assets": assets, "relevance_score": score})


def _text(value: str | None, maximum: int) -> str:
    if not value:
        return ""
    plain = re.sub(r"<[^>]+>", " ", unescape(value))
    return re.sub(r"\s+", " ", plain).strip()[:maximum]


def _canonical_url(value: str) -> str:
    parsed = urlparse(value)
    query = [(k, v) for k, v in parse_qsl(parsed.query, keep_blank_values=True)
             if not k.lower().startswith("utm_") and k.lower() not in {"fbclid", "gclid"}]
    return urlunparse(parsed._replace(fragment="", query=urlencode(query)))


def _normalized(value: str) -> str:
    return re.sub(r"\W+", " ", value.casefold().translate(str.maketrans("يك\u200c", "یک "))).strip()


def relevance(article: NewsArticle) -> tuple[list[str], int]:
    title, body = _normalized(article.title), _normalized(article.summary)
    extra = {
        "BTC": ("بیت کوین", "بیتکوین"), "ETH": ("اتریوم",), "USDT": ("تتر", "tether"),
        "USD": ("دلار", "dollar", "fed", "federal reserve"), "EUR": ("یورو", "euro", "ecb"),
        "GOLD18": ("طلا", "سکه", "gold"), "XAU": ("طلا", "gold"), "XAG": ("نقره", "silver"),
    }
    assets, score = [], 0
    for asset in SUPPORTED_ASSETS:
        terms = {_normalized(asset.symbol), _normalized(asset.name), *extra.get(asset.symbol, ())}
        # Exact word/phrase boundaries avoid e.g. SOL in a word or USD in USDT.
        headline = any(f" {term} " in f" {title} " for term in terms)
        description = any(f" {term} " in f" {body} " for term in terms)
        if headline or description:
            assets.append(asset.symbol)
            score += 4 if headline else 1
    if any(f" {term} " in f" {title} " for term in ("crypto", "cryptocurrency", "رمزارز", "ارز دیجیتال")):
        score += 2
    return assets, min(score, 16)


def rank_and_deduplicate(articles: list[NewsArticle]) -> list[NewsArticle]:
    kept: list[NewsArticle] = []
    # Take the latest original as representative; never delete source records.
    for article in sorted(articles, key=lambda a: a.published_at, reverse=True):
        title = _normalized(article.title)
        words = set(title.split())
        duplicate = False
        for prior in kept:
            if article.article_id == prior.article_id:
                duplicate = True
                break
            if article.language != prior.language or abs(article.published_at - prior.published_at) > timedelta(hours=48):
                continue
            other = _normalized(prior.title)
            if title == other and len(words) >= 3:
                duplicate = True
                break
            other_words = set(other.split())
            if (len(words) >= 6 and len(other_words) >= 6
                    and set(re.findall(r"\d+", title)) == set(re.findall(r"\d+", other))
                    and set(article.relevant_assets) == set(prior.relevant_assets)
                    and len(words & other_words) / len(words | other_words) >= 0.92
                    and SequenceMatcher(None, title, other).ratio() >= 0.92):
                duplicate = True
                break
        if not duplicate:
            kept.append(article)
    return sorted(kept, key=lambda a: (a.relevance_score, a.published_at), reverse=True)


def _parse_date(value: str | None) -> datetime | None:
    if not value:
        return None
    from email.utils import parsedate_to_datetime

    try:
        parsed = parsedate_to_datetime(value)
    except (TypeError, ValueError, OverflowError):
        return None
    return _utc(parsed)


def _utc(value: datetime) -> datetime:
    if value.tzinfo is None:
        return value.replace(tzinfo=timezone.utc)
    return value.astimezone(timezone.utc)
