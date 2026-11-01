from __future__ import annotations

from collections import defaultdict, deque
from threading import Lock
import time

from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.responses import JSONResponse, Response


class InMemoryRateLimitMiddleware(BaseHTTPMiddleware):
    """Small private-beta abuse guard.

    This is intentionally process-local. Production multi-worker deployment
    should replace it with a shared Redis-backed limiter without changing API
    contracts.
    """

    def __init__(self, app, *, limit_per_minute: int = 120) -> None:
        super().__init__(app)
        self.limit = max(10, min(limit_per_minute, 10_000))
        self._events: dict[str, deque[float]] = defaultdict(deque)
        self._lock = Lock()

    async def dispatch(self, request: Request, call_next) -> Response:
        if request.url.path.endswith("/health") or request.url.path.endswith("/ready"):
            return await call_next(request)
        client = request.client.host if request.client else "unknown"
        key = f"{client}:{request.url.path.split('/')[3] if request.url.path.startswith('/api/v1/') else 'root'}"
        now = time.monotonic()
        cutoff = now - 60.0
        with self._lock:
            bucket = self._events[key]
            while bucket and bucket[0] < cutoff:
                bucket.popleft()
            if len(bucket) >= self.limit:
                return JSONResponse(
                    status_code=429,
                    content={"detail": "Too many requests. Try again shortly."},
                    headers={"Retry-After": "60"},
                )
            bucket.append(now)
        return await call_next(request)
