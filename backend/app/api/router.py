from fastapi import APIRouter

from app.api.routes import assistant, auth, exchange, forecast, health, history, intelligence, market, paper, product, pulse

api_router = APIRouter()
api_router.include_router(assistant.router)
api_router.include_router(auth.router)
api_router.include_router(health.router)
api_router.include_router(market.router)
api_router.include_router(history.router)
api_router.include_router(history.market_router)
api_router.include_router(intelligence.router)
api_router.include_router(forecast.router)
api_router.include_router(forecast.forecasts_router)
api_router.include_router(forecast.performance_router)
api_router.include_router(paper.router)

api_router.include_router(product.router)
api_router.include_router(exchange.router)
api_router.include_router(pulse.router)
