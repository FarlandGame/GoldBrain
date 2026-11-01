from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, Request
from sqlalchemy.orm import Session
from sqlalchemy.exc import SQLAlchemyError

from app.api.dependencies import get_ai_service, get_news_service, get_identity
from app.core.security import require_client_access
from app.db.session import get_db
from app.schemas.intelligence import DeepAnalysisRequest, DeepAnalysisResponse, NewsResponse
from app.schemas.intelligence import NewsSummaryRequest, NewsSummaryResponse, NewsTranslationRequest, NewsTranslationResponse
from app.services.assistant import AssistantError
from app.services.news_ai import NewsAiService
from app.services.ai import AiNarrativeService
from app.services.forecasting import ForecastError, ForecastService
from app.services.news import NewsService

router = APIRouter(
    prefix="/intelligence",
    tags=["intelligence"],
    dependencies=[Depends(require_client_access)],
)
forecast_service = ForecastService()


@router.get("/news", response_model=NewsResponse)
async def news(
    refresh: bool = False,
    db: Session = Depends(get_db),
    service: NewsService = Depends(get_news_service),
) -> NewsResponse:
    del refresh  # Both paths respect the shared five-minute source cadence.
    try:
        snapshot = await service.refresh(db)
    except SQLAlchemyError as exc:
        raise HTTPException(status_code=503, detail={"code": "news_unavailable", "message": "News is temporarily unavailable."}) from exc
    if not snapshot.articles:
        raise HTTPException(status_code=503, detail={"code": "news_unavailable", "message": "News is temporarily unavailable."})
    return snapshot


def get_news_ai_service(request: Request) -> NewsAiService:
    return request.app.state.news_ai_service


def news_ai_error(exc: AssistantError) -> HTTPException:
    return HTTPException(status_code=exc.status, detail={"code": exc.code, "message": "News AI is temporarily unavailable. Please try again later."})


@router.post("/news/translations", response_model=NewsTranslationResponse, dependencies=[Depends(get_identity)])
async def translate_news(payload: NewsTranslationRequest, db: Session = Depends(get_db),
                         service: NewsAiService = Depends(get_news_ai_service)) -> NewsTranslationResponse:
    try:
        return await service.translate(db, payload.article_ids, payload.language)
    except AssistantError as exc:
        raise news_ai_error(exc) from exc


@router.post("/news/{article_id}/summary", response_model=NewsSummaryResponse, dependencies=[Depends(get_identity)])
async def summarize_news(article_id: str, payload: NewsSummaryRequest, db: Session = Depends(get_db),
                         service: NewsAiService = Depends(get_news_ai_service)) -> NewsSummaryResponse:
    try:
        return await service.summarize(db, article_id, payload.language)
    except AssistantError as exc:
        raise news_ai_error(exc) from exc


@router.post("/deep-analysis", response_model=DeepAnalysisResponse)
async def deep_analysis(
    payload: DeepAnalysisRequest,
    db: Session = Depends(get_db),
    news_service: NewsService = Depends(get_news_service),
    ai_service: AiNarrativeService = Depends(get_ai_service),
) -> DeepAnalysisResponse:
    try:
        forecast = forecast_service.generate(
            db,
            symbol=payload.symbol,
            horizon=payload.horizon,
            timeframe=payload.timeframe,
            persist=True,
        )
    except ForecastError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc

    if payload.refresh_news:
        news_snapshot = await news_service.refresh(db)
        articles = news_snapshot.articles
    else:
        articles = news_service.latest(db)
    symbol = forecast.symbol
    keywords = {
        "GOLD18": ("طلا", "سکه", "gold", "dollar", "دلار"),
        "XAU": ("طلا", "gold", "fed", "دلار", "dollar"),
        "XAG": ("نقره", "silver", "دلار", "dollar"),
        "USD": ("دلار", "ارز", "currency", "تحریم", "بانک مرکزی"),
        "USDT": ("تتر", "دلار", "رمزارز", "crypto"),
        "BTC": ("بیت", "bitcoin", "رمزارز", "crypto"),
        "ETH": ("اتریوم", "ethereum", "رمزارز", "crypto"),
    }.get(symbol, (symbol.lower(),))
    relevant = [
        article
        for article in articles
        if any(keyword.lower() in f"{article.title} {article.summary}".lower() for keyword in keywords)
    ][:8]
    move = (forecast.point_estimate / forecast.anchor_price - 1.0) * 100
    scenario_summary = (
        f"{symbol}: {forecast.direction} scenario, estimated move {move:+.2f}% over {forecast.horizon}; "
        f"confidence {forecast.confidence_score}/100 ({forecast.calibration_status})."
    )
    bullish = (
        f"Bullish case strengthens if price holds above {forecast.anchor_price:.4f} and momentum/news evidence improves; "
        f"model interval upper bound is {forecast.upper_bound:.4f}."
    )
    bearish = (
        f"Bearish case strengthens if the current regime breaks lower; model interval lower bound is {forecast.lower_bound:.4f}."
    )
    invalidation = [
        "A new high-impact political or macroeconomic event.",
        "A volatility regime shift outside the historical validation range.",
        "A material market-data/provider outage or stale quote.",
    ]
    evidence = {
        "forecast": forecast.model_dump(mode="json"),
        "news": [item.model_dump(mode="json") for item in relevant],
        "rules": {"no_guarantee": True, "numerical_forecast_not_from_llm": True},
    }
    narrative, model = await ai_service.summarize(evidence=evidence, language=payload.language)
    return DeepAnalysisResponse(
        symbol=symbol,
        horizon=forecast.horizon,
        forecast=forecast,
        relevant_news=relevant,
        scenario_summary=scenario_summary,
        bullish_scenario=bullish,
        bearish_scenario=bearish,
        invalidation_factors=invalidation,
        ai_narrative=narrative,
        ai_model=model,
        generated_at=datetime.now(timezone.utc),
    )
