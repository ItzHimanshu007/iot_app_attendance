"""Centralised configuration — reads .env once and exposes typed settings.

All configuration flows through this module. No other module should call
``os.getenv()`` directly.
"""

from __future__ import annotations

import sys
from functools import lru_cache

from pydantic_settings import BaseSettings

from app.core.logging import get_logger

logger = get_logger(__name__)

# ── Placeholder sentinel values ───────────────────────────────────────────────
# These are the strings that indicate the .env has NOT been configured yet.
_PLACEHOLDER_URL = "https://your-project.supabase.co"
_PLACEHOLDER_SERVICE_KEY = "your-service-key"
_PLACEHOLDER_ANON_KEY = "your-anon-key"
_PLACEHOLDER_JWT = "change-me-to-a-random-64-char-string"


class Settings(BaseSettings):
    """Application-wide settings loaded from environment variables / .env file."""

    # ── Supabase ──────────────────────────────────────────────────────────────
    supabase_url: str = _PLACEHOLDER_URL
    supabase_service_key: str = _PLACEHOLDER_SERVICE_KEY
    supabase_anon_key: str = _PLACEHOLDER_ANON_KEY

    # JWT secret — found in Supabase Dashboard → Project Settings → API → JWT Settings
    jwt_secret: str = _PLACEHOLDER_JWT

    # ── MQTT ──────────────────────────────────────────────────────────────────
    mqtt_broker: str = "localhost"
    mqtt_port: int = 1883
    mqtt_username: str = ""
    mqtt_password: str = ""

    # ── FastAPI ───────────────────────────────────────────────────────────────
    api_host: str = "0.0.0.0"
    api_port: int = 8000
    # Default to False (production-safe).
    # Local dev: set DEBUG=true in backend/.env
    # Render: set DEBUG=false (or leave unset) in environment variables.
    debug: bool = False
    allowed_origins: str = "*"

    # ── Attendance policy ─────────────────────────────────────────────────────
    # When True, students must have an active enrollment record for the session's
    # subject before attendance is accepted.
    # When False, any authenticated student who passes all other security checks
    # (JWT, device, token, duplicate, expiry) may record attendance.
    # Set via ENFORCE_SUBJECT_ENROLLMENT in backend/.env.
    enforce_subject_enrollment: bool = False

    model_config = {
        "env_file": ".env",
        "env_file_encoding": "utf-8",
        "case_sensitive": False,
    }

    @property
    def cors_origins(self) -> list[str]:
        """Parse ALLOWED_ORIGINS into a list."""
        if self.allowed_origins == "*":
            return ["*"]
        return [o.strip() for o in self.allowed_origins.split(",")]

    # ── Validation helpers ────────────────────────────────────────────────────

    @property
    def is_supabase_configured(self) -> bool:
        """True when Supabase URL and service key are real values."""
        return (
            self.supabase_url != _PLACEHOLDER_URL
            and not self.supabase_url.endswith("your-project.supabase.co")
            and "YOUR_PROJECT_REF" not in self.supabase_url
            and self.supabase_service_key != _PLACEHOLDER_SERVICE_KEY
            and self.supabase_service_key != ""
        )

    @property
    def is_jwt_configured(self) -> bool:
        """True when a real JWT secret has been set."""
        return (
            self.jwt_secret != _PLACEHOLDER_JWT
            and self.jwt_secret != ""
            and len(self.jwt_secret) >= 32
        )

    @property
    def is_mqtt_localhost(self) -> bool:
        """True when using default localhost broker (may not be running)."""
        return self.mqtt_broker in ("localhost", "127.0.0.1")


@lru_cache
def get_settings() -> Settings:
    """Return a cached Settings singleton."""
    return Settings()


def validate_startup_config(fatal: bool = False) -> list[str]:
    """Validate configuration on startup. Returns list of warning messages.

    Args:
        fatal: If True, call sys.exit(1) when critical values are missing.
               Set False for lenient startup (MQTT warnings only).

    Returns:
        List of warning strings. Empty list means all critical config is OK.
    """
    cfg = get_settings()
    warnings: list[str] = []
    errors: list[str] = []

    # ── Critical: Supabase ────────────────────────────────────────────────────
    if not cfg.is_supabase_configured:
        errors.append(
            "SUPABASE_URL and/or SUPABASE_SERVICE_KEY are not configured.\n"
            "  → Edit backend/.env and set real values from:\n"
            "    Supabase Dashboard → Project Settings → API"
        )

    if not cfg.is_jwt_configured:
        errors.append(
            "JWT_SECRET is not configured or is too short (< 32 chars).\n"
            "  → Set JWT_SECRET in backend/.env\n"
            "    Supabase Dashboard → Project Settings → API → JWT Settings → JWT Secret"
        )

    # ── Non-critical: MQTT ────────────────────────────────────────────────────
    if cfg.is_mqtt_localhost:
        warnings.append(
            f"MQTT_BROKER is '{cfg.mqtt_broker}' — broker may not be running. "
            "FastAPI will start normally; MQTT features need a running broker."
        )

    # ── Log everything ────────────────────────────────────────────────────────
    for w in warnings:
        logger.warning("CONFIG WARNING", detail=w)

    for e in errors:
        logger.error("CONFIG ERROR — STARTUP BLOCKED", detail=e)

    if errors and fatal:
        print("\n" + "=" * 60)
        print("FATAL: Backend cannot start — configuration is incomplete.")
        print("=" * 60)
        for e in errors:
            print(f"\n  ✗ {e}")
        print(
            "\nFix: Copy backend/.env.example to backend/.env"
            " and fill in your Supabase credentials.\n"
        )
        sys.exit(1)

    return warnings + errors
