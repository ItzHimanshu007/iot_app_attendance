"""Supabase client singleton (service-role key, backend only).

The client is created lazily on first use so that importing the app (e.g. in
tests) never triggers a network call. If Supabase is not configured a 503 with
an actionable message is raised instead of a confusing DNS error.
"""

from __future__ import annotations

from typing import Any

from supabase import create_client

from app.core.config import get_settings
from app.core.exceptions import AppError
from app.core.logging import get_logger

logger = get_logger(__name__)

_client: Any | None = None


class ConfigurationError(AppError):
    """Required configuration (e.g. Supabase URL) is missing."""

    def __init__(self, message: str) -> None:
        super().__init__(message, "CONFIGURATION_ERROR", 503)


def get_supabase() -> Any:
    """Return (and lazily create) the Supabase client."""
    global _client
    if _client is None:
        cfg = get_settings()
        if not cfg.is_supabase_configured:
            raise ConfigurationError(
                "Supabase is not configured. Set SUPABASE_URL and SUPABASE_SERVICE_KEY "
                "in backend/.env (Supabase Dashboard → Project Settings → API)."
            )
        logger.info("Creating Supabase client", url=cfg.supabase_url)
        _client = create_client(cfg.supabase_url, cfg.supabase_service_key)
    return _client


def set_supabase_client(client: Any | None) -> None:
    """Replace the singleton (used by tests to inject an in-memory fake)."""
    global _client
    _client = client
