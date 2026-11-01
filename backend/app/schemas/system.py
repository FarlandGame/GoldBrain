from datetime import datetime

from app.schemas.common import ApiModel


class HealthResponse(ApiModel):
    status: str
    service: str
    version: str
    environment: str
    timestamp: datetime


class Capability(ApiModel):
    name: str
    status: str
    phase: int
    note: str


class CapabilitiesResponse(ApiModel):
    capabilities: list[Capability]
