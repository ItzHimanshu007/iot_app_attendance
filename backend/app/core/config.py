"""Centralised configuration — reads .env once and exposes typed settings.

All configuration flows through this module. No other module should call
``os.getenv()`` directly.

Campus-specific policy (location, office hours, face threshold, geofence mode)
lives in the ``campus_settings`` table so admins can change it from the app.
This file only holds deployment settings and security tunables.
"""

from __future__ import annotations

import sys
from functools import lru_cache

from pydantic_settings import BaseSettings

from app.core.logging import get_logger

logger = get_logger(__name__)

_PLACEHOLDER_URL = "https://your-project-ref.supabase.co"
_PLACEHOLDER_SERVICE_KEY = "your-service-role-key"


class Settings(BaseSettings):
    """Application-wide settings loaded from environment variables / .env file."""

    # ── Supabase ──────────────────────────────────────────────────────────────
    supabase_url: str = _PLACEHOLDER_URL
    # Legacy "service_role" key or new "sb_secret_..." key. Backend only.
    supabase_service_key: str = _PLACEHOLDER_SERVICE_KEY
    # Optional — sent as `apikey` when fetching the public JWKS.
    supabase_anon_key: str = ""
    # Only needed for projects that still sign JWTs with the legacy HS256 secret.
    # New projects use asymmetric keys (ES256) verified through JWKS instead.
    jwt_secret: str = ""

    # ── FastAPI ───────────────────────────────────────────────────────────────
    debug: bool = False
    allowed_origins: str = "*"

    # ── Attendance security tunables ──────────────────────────────────────────
    # Seconds a challenge (camera step) stays valid.
    challenge_ttl_seconds: int = 120
    # Beacon token rotation window — MUST match TOKEN_WINDOW_SECONDS in firmware.
    beacon_window_seconds: int = 30
    # How many past windows are accepted when the challenge is requested
    # (1 = current or previous token, i.e. the phone saw it < ~60 s ago).
    beacon_challenge_past_windows: int = 1
    # How many past windows are accepted at submit time (covers the camera step).
    beacon_submit_past_windows: int = 5
    # Future windows accepted (ESP32 clock running slightly ahead).
    beacon_future_windows: int = 1
    # Number of random liveness steps the user must perform.
    liveness_steps_count: int = 2
    # Face enrollment sample limits.
    face_min_samples: int = 3
    face_max_samples: int = 10
    # Minimum similarity between enrollment samples (rejects mixed faces).
    face_enroll_consistency_threshold: float = 0.45
    # Reject submissions from emulators.
    block_emulators: bool = True

    model_config = {
        "env_file": ".env",
        "env_file_encoding": "utf-8",
        "case_sensitive": False,
        "extra": "ignore",
    }

    @property
    def cors_origins(self) -> list[str]:
        """Parse ALLOWED_ORIGINS into a list."""
        if self.allowed_origins.strip() == "*":
            return ["*"]
        return [o.strip() for o in self.allowed_origins.split(",") if o.strip()]

    @property
    def is_supabase_configured(self) -> bool:
        """True when Supabase URL and service key are real values."""
        return (
            bool(self.supabase_url)
            and self.supabase_url != _PLACEHOLDER_URL
            and "your-project" not in self.supabase_url
            and bool(self.supabase_service_key)
            and self.supabase_service_key != _PLACEHOLDER_SERVICE_KEY
        )


@lru_cache
def get_settings() -> Settings:
    """Return a cached Settings singleton."""
    return Settings()


def validate_startup_config(fatal: bool = False) -> list[str]:
    """Validate configuration on startup and return a list of problems.

    Args:
        fatal: If True, exit the process when critical values are missing.
    """
    cfg = get_settings()
    errors: list[str] = []

    if not cfg.is_supabase_configured:
        errors.append(
            "SUPABASE_URL and/or SUPABASE_SERVICE_KEY are not configured. "
            "Copy backend/.env.example to backend/.env and fill them in "
            "(Supabase Dashboard → Project Settings → API)."
        )

    for e in errors:
        logger.error("CONFIG ERROR", detail=e)

    if errors and fatal:
        print("\nFATAL: backend configuration is incomplete:")
        for e in errors:
            print(f"  ✗ {e}")
        sys.exit(1)

    return errors
