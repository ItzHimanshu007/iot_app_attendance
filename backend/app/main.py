"""Staff Attendance API — FastAPI entry point.

Sits between the Flutter staff app and Supabase. The ESP32 beacons are fully
offline from the backend's point of view: they compute their rotating tokens
themselves, and the backend recomputes them to verify what the phone heard.
"""

from __future__ import annotations

from collections.abc import AsyncGenerator
from contextlib import asynccontextmanager
from datetime import UTC, datetime
from typing import Any

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from app.api.v1.router import v1_router
from app.core.config import get_settings, validate_startup_config
from app.core.exceptions import AppError
from app.core.logging import get_logger, request_id_ctx, setup_logging
from app.middleware.request_context import RequestContextMiddleware

logger = get_logger(__name__)

VERSION = "1.0.0"


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncGenerator[None, None]:
    """Configure logging and validate configuration on startup."""
    settings = get_settings()
    setup_logging(debug=settings.debug)
    logger.info("Starting Staff Attendance API", version=VERSION)
    # Production (DEBUG=false) refuses to start without Supabase credentials.
    validate_startup_config(fatal=not settings.debug)
    yield
    logger.info("Shutting down")


settings = get_settings()

app = FastAPI(
    title="Staff Attendance API",
    version=VERSION,
    description=(
        "Staff check-in / check-out with ESP32 BLE beacons, on-device face "
        "recognition and GPS geofencing (PS 23 — Smart Campus)."
    ),
    lifespan=lifespan,
)

app.add_middleware(RequestContextMiddleware)
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins,
    allow_credentials=settings.cors_origins != ["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


def _envelope(status: int, code: str, message: str) -> JSONResponse:
    return JSONResponse(
        status_code=status,
        content={
            "error": {
                "code": code,
                "message": message,
                "timestamp": datetime.now(UTC).isoformat(),
                "request_id": request_id_ctx.get(),
            }
        },
    )


@app.exception_handler(AppError)
async def app_error_handler(request: Request, exc: AppError) -> JSONResponse:
    """Typed errors → JSON envelope."""
    log = logger.warning if exc.status_code < 500 else logger.error
    log("AppError", code=exc.code, status=exc.status_code, message=exc.message)
    return _envelope(exc.status_code, exc.code, exc.message)


@app.exception_handler(RequestValidationError)
async def validation_error_handler(request: Request, exc: RequestValidationError) -> JSONResponse:
    """Pydantic validation errors → same envelope (first problem only)."""
    errors: list[Any] = list(exc.errors())
    first = errors[0] if errors else {}
    location = ".".join(str(p) for p in first.get("loc", []) if p != "body")
    message = f"{location}: {first.get('msg', 'invalid value')}" if location else "Invalid request"
    return _envelope(422, "VALIDATION_ERROR", message)


@app.exception_handler(Exception)
async def unhandled_error_handler(request: Request, exc: Exception) -> JSONResponse:
    """Never leak stack traces."""
    logger.error("Unhandled exception", error=str(exc), exc_info=True)
    return _envelope(500, "INTERNAL_ERROR", "An unexpected error occurred")


app.include_router(v1_router)


@app.get("/health", tags=["infra"])
async def health() -> dict[str, str]:
    """Liveness probe (also used to wake a sleeping Render instance)."""
    return {"status": "healthy", "service": "staff-attendance-api", "version": VERSION}


@app.get("/readyz", tags=["infra"])
async def readyz() -> dict[str, Any]:
    """Configuration check."""
    cfg = get_settings()
    issues = validate_startup_config(fatal=False)
    return {
        "status": "ready" if not issues else "degraded",
        "supabase_configured": cfg.is_supabase_configured,
        "legacy_hs256_secret_configured": bool(cfg.jwt_secret),
        "beacon_window_seconds": cfg.beacon_window_seconds,
        "issues": issues,
    }
