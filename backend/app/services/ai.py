from __future__ import annotations

import json
from urllib.parse import urlparse

import httpx

from app.core.config import Settings


class AiNarrativeService:
    """Optional OpenAI-compatible narrative layer.

    Numerical forecasts never come from this service. It only summarizes the
    structured evidence supplied by the deterministic/ML forecast pipeline.
    """

    def __init__(self, settings: Settings, client: httpx.AsyncClient | None = None) -> None:
        self.settings = settings
        self._owns_client = client is None
        self.client = client or httpx.AsyncClient(timeout=httpx.Timeout(35.0), follow_redirects=False)

    @property
    def configured(self) -> bool:
        parsed = urlparse(self.settings.ai_base_url)
        return bool(self.settings.ai_api_key.strip() and parsed.scheme == "https" and parsed.hostname)

    async def close(self) -> None:
        if self._owns_client:
            await self.client.aclose()

    async def summarize(self, *, evidence: dict, language: str) -> tuple[str | None, str | None]:
        if not self.configured:
            return None, None
        base = self.settings.ai_base_url.rstrip("/")
        payload = {
            "model": self.settings.ai_model,
            "temperature": 0.2,
            "messages": [
                {
                    "role": "system",
                    "content": (
                        "You are GoldBrain's evidence narrator. Never invent prices, probabilities, news, "
                        "or guarantees. Explain only the supplied JSON evidence. Explicitly mention uncertainty."
                    ),
                },
                {
                    "role": "user",
                    "content": f"Language: {language}. Evidence JSON:\n{json.dumps(evidence, ensure_ascii=False)}",
                },
            ],
        }
        response = await self.client.post(
            f"{base}/chat/completions",
            headers={"Authorization": f"Bearer {self.settings.ai_api_key}", "Content-Type": "application/json"},
            json=payload,
        )
        if response.status_code < 200 or response.status_code >= 300:
            return None, None
        body = response.json()
        choices = body.get("choices") if isinstance(body, dict) else None
        if not isinstance(choices, list) or not choices:
            return None, None
        message = choices[0].get("message") if isinstance(choices[0], dict) else None
        text = message.get("content") if isinstance(message, dict) else None
        if not isinstance(text, str) or not text.strip():
            return None, None
        return text.strip()[:12000], self.settings.ai_model
