from __future__ import annotations

from dataclasses import dataclass
from typing import Protocol


@dataclass(frozen=True)
class ExchangeOrderResult:
    adapter: str
    sandbox: bool
    status: str
    external_order_id: str | None = None


class ExchangeAdapter(Protocol):
    name: str
    sandbox: bool

    async def health(self) -> bool: ...


class MockExchangeAdapter:
    """Development-only adapter contract.

    Real exchange credentials and real-money order execution are intentionally
    absent from the private-beta foundation. Paper trading remains the only
    executable order path in this repository.
    """

    name = "mock"
    sandbox = True

    async def health(self) -> bool:
        return True
