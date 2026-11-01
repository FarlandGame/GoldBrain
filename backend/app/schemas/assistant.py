from __future__ import annotations

from typing import Literal

from pydantic import Field

from app.schemas.common import ApiModel


class AssistantMessage(ApiModel):
    role: Literal["user", "assistant"]
    content: str = Field(min_length=1, max_length=4000)


class AssistantRequest(ApiModel):
    messages: list[AssistantMessage] = Field(min_length=1, max_length=24)
    language: Literal["english", "persian", "japanese", "russian", "chinese", "arabic", "turkish", "french"] = "persian"
    tone: Literal["balanced", "concise", "detailed"] = "balanced"
    temperature: float = Field(default=0.35, ge=0, le=1)
    market_context: bool = True
    display_currency: str = Field(default="IRT", max_length=12)


class AssistantEvidence(ApiModel):
    tool: str
    data: dict


class AssistantResponse(ApiModel):
    text: str
    model: str
    evidence: list[AssistantEvidence] = []
    history_trimmed: bool = False
