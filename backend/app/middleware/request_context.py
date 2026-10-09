"""Request context middleware — injects request ID and logs every request.

Sets context variables used by the structured logger so all log lines
within a request carry the same correlation ID.
"""

from __future__ import annotations

import time
import uuid

from fastapi import Request, Response
from starlette.middleware.base import BaseHTTPMiddleware, RequestResponseEndpoint

from app.core.logging import get_logger, request_id_ctx, user_id_ctx, user_role_ctx

logger = get_logger(__name__)


class RequestContextMiddleware(BaseHTTPMiddleware):
    """Injects request-ID, clears user context, and logs request timing."""

    async def dispatch(self, request: Request, call_next: RequestResponseEndpoint) -> Response:
        # Generate and set request ID
        request_id = str(uuid.uuid4())
        request.state.request_id = request_id
        request_id_ctx.set(request_id)

        # Reset user context (will be set by auth dependency if applicable)
        user_id_ctx.set(None)
        user_role_ctx.set(None)

        # Log request start
        start = time.perf_counter()
        method = request.method
        path = request.url.path

        logger.info(
            "Request started",
            method=method,
            path=path,
            client=request.client.host if request.client else "unknown",
        )

        response = await call_next(request)

        # Log request completion
        duration_ms = round((time.perf_counter() - start) * 1000, 2)
        response.headers["X-Request-ID"] = request_id
        response.headers["X-Response-Time"] = f"{duration_ms}ms"

        logger.info(
            "Request completed",
            method=method,
            path=path,
            status=response.status_code,
            duration_ms=duration_ms,
        )

        return response
