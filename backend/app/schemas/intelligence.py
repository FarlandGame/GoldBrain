from __future__ import annotations

from datetime import datetime

from typing import Literal

from pydantic import Field

from app.schemas.common import ApiModel
from app.schemas.forecast import ForecastResponse


class NewsArticle(ApiModel):
    article_id: str
    title: str
    summary: str
    source: str
    category: str
    language: str
    url: str
    published_at: datetime
    fetched_at: datetime | None = None
    source_information_url: str | None = None
    relevant_assets: list[str] = Field(default_factory=list)
    relevance_score: int = 0


class NewsResponse(ApiModel):
    articles: list[NewsArticle]
    source_errors: dict[str, str]
    fetched_at: datetime
    from_cache: bool = False
    polling_interval_seconds: int = 300


NewsLanguage = Literal["english", "persian", "japanese", "russian", "chinese", "arabic", "turkish", "french"]


class NewsSummaryRequest(ApiModel):
    language: NewsLanguage = "persian"


class NewsSummaryResponse(ApiModel):
    article_id: str
    language: str
    text: str
    model: str
    source_url: str
    from_cache: bool = False


class NewsTranslationRequest(ApiModel):
    article_ids: list[str] = Field(min_length=1, max_length=6)
    language: NewsLanguage = "persian"


class NewsTranslation(ApiModel):
    article_id: str
    language: str
    title: str
    summary: str
    category: str


class NewsTranslationResponse(ApiModel):
    translations: list[NewsTranslation]
    model: str
    from_cache: bool = False


class DeepAnalysisRequest(ApiModel):
    symbol: str
    horizon: str = "12h"
    timeframe: str = "1h"
    language: str = "fa"
    refresh_news: bool = False


class DeepAnalysisResponse(ApiModel):
    symbol: str
    horizon: str
    forecast: ForecastResponse
    relevant_news: list[NewsArticle]
    scenario_summary: str
    bullish_scenario: str
    bearish_scenario: str
    invalidation_factors: list[str]
    ai_narrative: str | None = None
    ai_model: str | None = None
    generated_at: datetime
