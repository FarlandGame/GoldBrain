from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel

from app.api.dependencies import get_country_pulse_service
from app.core.security import require_client_access
from app.services.country_pulse_data import COUNTRY_INDEX, WINDOWS, CountryPulseDataService


class IndexPoint(BaseModel):
    time: str
    close: float


class CountryPulseEvidence(BaseModel):
    country: str
    window: str
    index_symbol: str
    index_name: str
    currency: str
    unit: str
    index_provider: str
    index_source_url: str
    index_status: str
    index_points: list[IndexPoint]
    last_observation_at: str | None
    news_provider: str
    news_status: str
    news_tone: float | None
    news_source_url: str
    checked_at: str


router = APIRouter(prefix="/pulse", tags=["pulse"], dependencies=[Depends(require_client_access)])


@router.get("/countries/{country}", response_model=CountryPulseEvidence)
async def country_evidence(
    country: str,
    window: str = "24h",
    service: CountryPulseDataService = Depends(get_country_pulse_service),
) -> CountryPulseEvidence:
    if country not in COUNTRY_INDEX or window not in WINDOWS:
        raise HTTPException(status_code=404, detail="Unsupported country or window")
    return CountryPulseEvidence.model_validate(await service.get(country, window))
