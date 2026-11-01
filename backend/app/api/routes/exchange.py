from fastapi import APIRouter, Depends

from app.api.dependencies import get_identity
from app.schemas.product import ExchangeCapabilities
from app.services.auth import Identity

router = APIRouter(prefix="/exchange", tags=["exchange"])


@router.get("/capabilities", response_model=ExchangeCapabilities)
def capabilities(identity: Identity = Depends(get_identity)) -> ExchangeCapabilities:
    _ = identity
    return ExchangeCapabilities(
        real_money_enabled=False,
        adapters=["mock"],
        note=(
            "Private beta includes only a sandbox/mock adapter contract. "
            "Use Paper Trading for executable testing; real-money adapters are not enabled."
        ),
    )
