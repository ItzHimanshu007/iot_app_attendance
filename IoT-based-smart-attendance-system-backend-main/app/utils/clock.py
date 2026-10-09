"""UTC-aware datetime helpers.

All timestamps in the system are UTC. These helpers ensure consistent
timezone handling across the codebase.
"""

from __future__ import annotations

from datetime import UTC, datetime


def utc_now() -> datetime:
    """Return the current UTC datetime (timezone-aware)."""
    return datetime.now(UTC)


def utc_iso(dt: datetime | None = None) -> str:
    """Format a datetime as an ISO-8601 string. Defaults to now."""
    if dt is None:
        dt = utc_now()
    return dt.isoformat()
