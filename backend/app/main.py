from __future__ import annotations

from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException, Request
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from app.api.router import api_router
from app.core.config import get_settings
from app.core.rate_limit import InMemoryRateLimitMiddleware
from app.db.base import Base
from app.db.session import engine
from app.services.market_data import MarketDataService
from app.services.news import NewsService
from app.services.news_ai import NewsAiService
from app.services.country_pulse_data import CountryPulseDataService
from app.services.ai import AiNarrativeService
from app.services.assistant import AssistantService

# Import models before optional create_all so SQLAlchemy knows the metadata.
from app import models as _models  # noqa: F401


@asynccontextmanager
async def lifespan(app: FastAPI):
    settings = get_settings()
    if settings.auto_create_tables and settings.environment in {"development", "test"}:
        Base.metadata.create_all(bind=engine)
    app.state.market_service = MarketDataService(settings)
    app.state.news_service = NewsService()
    app.state.country_pulse_service = CountryPulseDataService()
    app.state.ai_service = AiNarrativeService(settings)
    app.state.assistant_service = AssistantService(settings)
    app.state.news_ai_service = NewsAiService(app.state.assistant_service)
    try:
        yield
    finally:
        await app.state.market_service.close()
        await app.state.news_service.close()
        await app.state.country_pulse_service.close()
        await app.state.ai_service.close()
        await app.state.assistant_service.close()


def create_app() -> FastAPI:
    settings = get_settings()
    app = FastAPI(
        title=settings.app_name,
        version=settings.app_version,
        debug=settings.debug,
        lifespan=lifespan,
        docs_url="/docs" if settings.environment != "production" else None,
        redoc_url="/redoc" if settings.environment != "production" else None,
    )

    @app.exception_handler(HTTPException)
    async def http_error_handler(request: Request, exc: HTTPException) -> JSONResponse:
        del request
        detail = exc.detail
        message = detail if isinstance(detail, str) else detail.get("message", "Request failed.") if isinstance(detail, dict) else "Request failed."
        code = detail.get("code", f"HTTP_{exc.status_code}") if isinstance(detail, dict) else f"HTTP_{exc.status_code}"
        return JSONResponse(
            status_code=exc.status_code,
            headers=exc.headers,
            content={"detail": detail, "error": {"code": code, "message": message}},
        )

    @app.exception_handler(RequestValidationError)
    async def validation_error_handler(request: Request, exc: RequestValidationError) -> JSONResponse:
        del request
        # Pydantic includes submitted values/context by default. Passwords,
        # codes and tokens must never be echoed in validation responses.
        errors = [{key: value for key, value in item.items() if key not in {"input", "ctx"}} for item in exc.errors()]
        return JSONResponse(
            status_code=422,
            content={
                "detail": errors,
                "error": {"code": "VALIDATION_ERROR", "message": "Request validation failed.", "details": errors},
            },
        )
    app.add_middleware(InMemoryRateLimitMiddleware, limit_per_minute=settings.rate_limit_per_minute)
    if settings.parsed_cors_origins:
        app.add_middleware(
            CORSMiddleware,
            allow_origins=settings.parsed_cors_origins,
            allow_credentials=False,
            allow_methods=["GET", "POST", "DELETE", "OPTIONS"],
            allow_headers=["Authorization", "Content-Type", "X-GoldBrain-Key"],
        )
    app.include_router(api_router, prefix=settings.api_v1_prefix)
    return app


app = create_app()
