from __future__ import annotations

from datetime import datetime

from app.schemas.common import ApiModel


class WatchlistItem(ApiModel):
    symbol: str
    created_at: datetime


class WatchlistResponse(ApiModel):
    items: list[WatchlistItem]


class WatchlistRequest(ApiModel):
    symbol: str


class PreferencesResponse(ApiModel):
    preferences: dict[str, object]
    updated_at: datetime


class PreferencesRequest(ApiModel):
    preferences: dict[str, object]
