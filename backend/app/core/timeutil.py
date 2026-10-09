"""Time helpers — everything is stored in UTC, displayed in the campus timezone."""

from __future__ import annotations

from datetime import UTC, date, datetime, time, timedelta
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

DEFAULT_TZ = "Asia/Kolkata"


def now_utc() -> datetime:
    """Current UTC time (patched in tests)."""
    return datetime.now(UTC)


def campus_zone(name: str | None) -> ZoneInfo:
    """ZoneInfo for the campus, falling back to Asia/Kolkata."""
    try:
        return ZoneInfo(name or DEFAULT_TZ)
    except (ZoneInfoNotFoundError, ValueError):
        return ZoneInfo(DEFAULT_TZ)


def local_today(tz: ZoneInfo, at: datetime | None = None) -> date:
    """Today's date on campus."""
    return (at or now_utc()).astimezone(tz).date()


def parse_time(value: str | time | None, default: time) -> time:
    """Parse 'HH:MM[:SS]' from the database."""
    if isinstance(value, time):
        return value
    if not value:
        return default
    parts = [int(p) for p in str(value).split(":")[:3]]
    while len(parts) < 3:
        parts.append(0)
    return time(parts[0], parts[1], parts[2])


def is_late(check_in: datetime, tz: ZoneInfo, work_start: time, grace_minutes: int) -> bool:
    """True when the local check-in time is after start + grace."""
    local = check_in.astimezone(tz)
    cutoff = datetime.combine(local.date(), work_start, tzinfo=tz) + timedelta(
        minutes=grace_minutes
    )
    return local > cutoff


def parse_ts(value: str | datetime | None) -> datetime | None:
    """Parse an ISO timestamp from PostgREST (handles 'Z')."""
    if value is None or isinstance(value, datetime):
        return value
    return datetime.fromisoformat(str(value).replace("Z", "+00:00"))
