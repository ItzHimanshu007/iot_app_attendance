"""Supabase client singleton — reuses a single connection across the app.

The client is lazily created on first use. If Supabase is not configured
(placeholder URL/key), a ConfigurationError is raised with an actionable
message pointing to .env, rather than triggering a DNS lookup to an
invalid hostname.
"""

from __future__ import annotations

from supabase import Client, create_client

from app.core.config import get_settings
from app.core.exceptions import AppError
from app.core.logging import get_logger

logger = get_logger(__name__)

_client: Client | None = None


class ConfigurationError(AppError):
    """Raised when required configuration (e.g. Supabase URL) is missing."""

    def __init__(self, message: str) -> None:
        super().__init__(
            message=message,
            code="CONFIGURATION_ERROR",
            status_code=503,
        )


def get_supabase() -> Client:
    """Return (and lazily create) the Supabase client.

    Raises:
        ConfigurationError: If SUPABASE_URL or SUPABASE_SERVICE_KEY are
            placeholder values. This prevents a DNS lookup to
            'your-project.supabase.co' (the root cause of `getaddrinfo failed`).
    """
    global _client
    if _client is None:
        cfg = get_settings()

        # Guard: fail fast with a clear message rather than a network error
        if not cfg.is_supabase_configured:
            raise ConfigurationError(
                "Supabase is not configured. "
                "Set SUPABASE_URL and SUPABASE_SERVICE_KEY in backend/.env — "
                "values are available at: "
                "Supabase Dashboard → Project Settings → API"
            )

        logger.info("Creating Supabase client", url=cfg.supabase_url)
        _client = create_client(cfg.supabase_url, cfg.supabase_service_key)

    return _client


def reset_supabase_client() -> None:
    """Reset the singleton (test helper — do not call in production)."""
    global _client
    _client = None
