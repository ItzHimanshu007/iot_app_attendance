"""Smart Campus Attendance — FastAPI orchestrator.

This is the central backend that sits between the Flutter app,
Supabase database, and MQTT broker (which drives ESP32 beacons).
"""

from __future__ import annotations

import asyncio
from collections.abc import AsyncGenerator
from contextlib import asynccontextmanager
from datetime import UTC, datetime

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from app.api.v1.router import v1_router
from app.core.config import get_settings, validate_startup_config
from app.core.exceptions import AppError
from app.core.logging import get_logger, request_id_ctx, setup_logging
from app.middleware.request_context import RequestContextMiddleware
from app.mqtt.publisher import disconnect as mqtt_disconnect
from app.mqtt.publisher import get_mqtt_client
from app.mqtt.subscriber import start_subscriber
from app.services.session_service import auto_expire_sessions, rotate_all_active_sessions
from app.services.token_service import TOKEN_ROTATION_INTERVAL_SECONDS

logger = get_logger(__name__)


# ── Background task: auto-expire sessions every 60 seconds ────────────────────


async def _session_expiry_loop() -> None:
    """Periodically close expired sessions."""
    logger.info("Session expiry loop started", interval_seconds=60)
    while True:
        try:
            count = await asyncio.get_event_loop().run_in_executor(None, auto_expire_sessions)
            if count > 0:
                logger.info("Auto-expire sweep", expired_count=count)
        except Exception as e:
            logger.error("Auto-expire sweep failed", error=str(e))
        await asyncio.sleep(60)


# ── Background task: rotate beacon tokens every TOKEN_ROTATION_INTERVAL_SECONDS ─


async def _token_rotation_loop() -> None:
    """Periodically push a fresh HMAC token to every active classroom's ESP32.

    Sleeps for one full interval before the first rotation so the ESP32
    has time to receive and apply the initial token that was already sent
    by publish_start_session() at session creation.

    No-op when FIXED_TOKEN_MODE=True (rotate_all_active_sessions() returns 0).

    rotate_all_active_sessions() performs synchronous Supabase I/O and may
    block on paho retry sleeps, so it is dispatched to the default
    ThreadPoolExecutor via run_in_executor to avoid stalling the event loop.
    """
    logger.info(
        "Automatic token rotation service started",
        interval=TOKEN_ROTATION_INTERVAL_SECONDS,
    )
    while True:
        await asyncio.sleep(TOKEN_ROTATION_INTERVAL_SECONDS)
        try:
            loop = asyncio.get_event_loop()
            count = await loop.run_in_executor(None, rotate_all_active_sessions)
            if count > 0:
                logger.info("Token rotation sweep complete", rotated_count=count)
        except Exception as e:
            logger.error("Token rotation sweep failed", error=str(e))


# ── Lifespan ──────────────────────────────────────────────────────────────────


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncGenerator[None, None]:
    """Startup: configure logging, validate config, MQTT, background tasks. Shutdown: cleanup."""
    settings = get_settings()
    setup_logging(debug=settings.debug)
    logger.info("Starting Smart Campus Attendance API v0.2.0")

    # Validate configuration.
    # In production (DEBUG=false), fatal=True causes sys.exit(1) if Supabase
    # credentials are missing — fail fast rather than serve broken responses.
    # In development (DEBUG=true), fatal=False gives a warning and continues.
    validate_startup_config(fatal=not settings.debug)

    # Start MQTT and subscriber — warning only if broker unavailable
    try:
        client = get_mqtt_client()
        start_subscriber(client)
    except Exception as e:
        logger.warning("MQTT not available at startup — continuing without MQTT", error=str(e))

    # Start background session expiry sweep
    expiry_task = asyncio.create_task(_session_expiry_loop())

    # Start automatic token rotation loop
    rotation_task = asyncio.create_task(_token_rotation_loop())

    yield

    # Shutdown — cancel both background tasks cleanly
    expiry_task.cancel()
    rotation_task.cancel()
    mqtt_disconnect()
    logger.info("Shutting down")


# ── App ───────────────────────────────────────────────────────────────────────

settings = get_settings()

app = FastAPI(
    title="Smart Campus Attendance API",
    version="0.2.0",
    description=(
        "Orchestrator for IoT-based attendance — manages sessions, "
        "pushes MQTT commands to ESP32 beacons, validates attendance, "
        "and enforces device locking via Supabase."
    ),
    lifespan=lifespan,
)


# ── Middleware (order matters: outermost first) ───────────────────────────────

app.add_middleware(RequestContextMiddleware)

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


# ── Global exception handlers ────────────────────────────────────────────────


@app.exception_handler(AppError)
async def app_error_handler(request: Request, exc: AppError) -> JSONResponse:
    """Convert typed AppErrors into consistent error envelopes."""
    request_id = request_id_ctx.get()
    log_method = logger.warning if exc.status_code < 500 else logger.error
    log_method(
        "AppError",
        code=exc.code,
        status=exc.status_code,
        message=exc.message,
    )
    return JSONResponse(
        status_code=exc.status_code,
        content={
            "error": {
                "code": exc.code,
                "message": exc.message,
                "timestamp": datetime.now(UTC).isoformat(),
                "request_id": request_id,
            }
        },
    )


@app.exception_handler(Exception)
async def unhandled_error_handler(request: Request, exc: Exception) -> JSONResponse:
    """Catch-all for unhandled exceptions — never leak stack traces."""
    request_id = request_id_ctx.get()
    logger.error("Unhandled exception", error=str(exc), exc_info=True)
    return JSONResponse(
        status_code=500,
        content={
            "error": {
                "code": "INTERNAL_ERROR",
                "message": "An unexpected error occurred",
                "timestamp": datetime.now(UTC).isoformat(),
                "request_id": request_id,
            }
        },
    )


# ── Routers ───────────────────────────────────────────────────────────────────

app.include_router(v1_router)


# ── Health check (no auth required) ──────────────────────────────────────────


@app.get("/health", tags=["infra"])
async def health() -> dict:
    """Liveness probe — returns service identity and version."""
    return {
        "status": "healthy",
        "service": "smart-campus-attendance-api",
        "version": "0.2.0",
    }


@app.get("/readyz", tags=["infra"])
async def readyz() -> dict:
    """Readiness probe — returns configuration and connectivity status.

    Use this to verify your .env is correctly configured before
    running the full test flow.
    """
    cfg = get_settings()
    issues = []
    if not cfg.is_supabase_configured:
        issues.append("Supabase not configured — set SUPABASE_URL and SUPABASE_SERVICE_KEY in .env")
    if not cfg.is_jwt_configured:
        issues.append("JWT_SECRET not configured — set JWT_SECRET in .env")

    return {
        "status": "ready" if not issues else "degraded",
        "supabase_configured": cfg.is_supabase_configured,
        "jwt_configured": cfg.is_jwt_configured,
        "mqtt_broker": cfg.mqtt_broker,
        "mqtt_localhost": cfg.is_mqtt_localhost,
        "api_url": f"http://{cfg.api_host}:{cfg.api_port}",
        "issues": issues,
    }
