"""Pass-through to Supabase Auth for phones whose network blocks supabase.co.

In February 2026 several Indian ISPs (Jio, Airtel, ACT Fibernet) blocked
``*.supabase.co``, and some connections still fail ("Software caused connection
abort"). Sign-in then breaks even though this backend works fine.

Point the app's ``SUPABASE_URL`` at ``https://<this-backend>/supabase`` and its
Auth calls arrive here and are forwarded to the real project
(``settings.supabase_url``). Only the Auth API (``/auth/v1/...``) is forwarded:
it is all the app uses, and every other path is a 404. Nothing is stored.
"""

from __future__ import annotations

import httpx
from fastapi import APIRouter, Request, Response
from fastapi.responses import JSONResponse

from app.core.config import get_settings
from app.core.logging import get_logger

logger = get_logger(__name__)

router = APIRouter(prefix="/supabase", include_in_schema=False)

# Connection-level headers and ones httpx recomputes are not forwarded.
_DROP_REQUEST = {
    "host",
    "content-length",
    "connection",
    "keep-alive",
    "transfer-encoding",
    "te",
    "trailer",
    "upgrade",
    "accept-encoding",
    "proxy-authorization",
    "proxy-connection",
}
# httpx has already decoded the body, so length/encoding must be recomputed.
_DROP_RESPONSE = {
    "content-length",
    "content-encoding",
    "transfer-encoding",
    "connection",
    "keep-alive",
}

_client: httpx.AsyncClient | None = None


def _http() -> httpx.AsyncClient:
    global _client
    if _client is None:
        _client = httpx.AsyncClient(timeout=httpx.Timeout(20.0))
    return _client


def set_http_client(client: httpx.AsyncClient | None) -> None:
    """Swap the upstream HTTP client (tests)."""
    global _client
    _client = client


@router.api_route("/auth/v1/{path:path}", methods=["GET", "POST", "PUT", "PATCH", "DELETE"])
async def auth_proxy(path: str, request: Request) -> Response:
    """Forward one Supabase Auth request and return its response unchanged."""
    if any(part in (".", "..") for part in path.split("/")):
        return JSONResponse(status_code=404, content={"detail": "Not Found"})

    base = get_settings().supabase_url.rstrip("/")
    headers = {k: v for k, v in request.headers.items() if k.lower() not in _DROP_REQUEST}
    try:
        upstream = await _http().request(
            request.method,
            f"{base}/auth/v1/{path}",
            params=request.query_params.multi_items(),
            content=await request.body(),
            headers=headers,
        )
    except httpx.HTTPError as e:
        logger.warning("Supabase Auth unreachable", error=str(e), path=path)
        return JSONResponse(
            status_code=502,
            content={
                "code": "upstream_unreachable",
                "msg": "Could not reach the login service. Please try again.",
            },
        )

    out = {k: v for k, v in upstream.headers.items() if k.lower() not in _DROP_RESPONSE}
    return Response(content=upstream.content, status_code=upstream.status_code, headers=out)
