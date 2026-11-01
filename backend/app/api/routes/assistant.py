from fastapi import APIRouter, Depends, HTTPException, Request
from sqlalchemy.orm import Session

from app.api.dependencies import get_identity, get_market_service
from app.db.session import get_db
from app.schemas.assistant import AssistantRequest, AssistantResponse
from app.api.assistant_tools import AssistantDataTools
from app.services.assistant import AssistantError, AssistantService
from app.services.market_data import MarketDataService

router = APIRouter(prefix="/assistant", tags=["assistant"], dependencies=[Depends(get_identity)])


def get_assistant_service(request: Request) -> AssistantService:
    return request.app.state.assistant_service


@router.post("/chat", response_model=AssistantResponse)
async def chat(
    payload: AssistantRequest,
    db: Session = Depends(get_db),
    market: MarketDataService = Depends(get_market_service),
    assistant: AssistantService = Depends(get_assistant_service),
) -> AssistantResponse:
    tools = AssistantDataTools(db, market, payload.display_currency)
    try:
        return await assistant.chat(payload, tools.execute)
    except AssistantError as exc:
        # Never return an upstream response, traceback, URL or request body.
        raise HTTPException(status_code=exc.status, detail={
            "code": exc.code, "message": "The assistant is temporarily unavailable. Please try again later.",
        }) from exc
