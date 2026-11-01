from __future__ import annotations

from pydantic import BaseModel, ConfigDict


class ApiModel(BaseModel):
    model_config = ConfigDict(extra="forbid")


class ApiError(ApiModel):
    code: str
    message: str
    details: object | None = None
