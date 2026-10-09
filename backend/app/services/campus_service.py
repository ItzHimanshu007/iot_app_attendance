"""Campus settings (single row, editable by admins)."""

from __future__ import annotations

from typing import Any

from app.core.exceptions import ValidationError
from app.core.timeutil import campus_zone
from app.repositories.campus_repo import CampusSettingsRepository

_repo = CampusSettingsRepository()

DEFAULTS: dict[str, Any] = {
    "id": 1,
    "campus_name": "My Campus",
    "timezone": "Asia/Kolkata",
    "latitude": None,
    "longitude": None,
    "radius_m": 500,
    "geofence_mode": "flag",
    "max_location_accuracy_m": 150,
    "work_start_time": "09:00:00",
    "late_grace_minutes": 15,
    "face_match_threshold": 0.55,
}


def get_campus() -> dict[str, Any]:
    """Current settings merged over safe defaults."""
    row = _repo.get() or {}
    merged = dict(DEFAULTS)
    for key, value in row.items():
        if value is not None or key in ("latitude", "longitude"):
            merged[key] = value
    return merged


def update_campus(data: dict[str, Any]) -> dict[str, Any]:
    """Validate and persist a partial update."""
    clean = {k: v for k, v in data.items() if v is not None}
    if "timezone" in clean:
        tz = campus_zone(clean["timezone"])
        if str(tz) != clean["timezone"]:
            raise ValidationError(f"Unknown timezone '{clean['timezone']}'", "INVALID_TIMEZONE")
    if "work_start_time" in clean:
        clean["work_start_time"] = clean["work_start_time"].isoformat()
    if not clean:
        return get_campus()
    _repo.save(clean)
    return get_campus()
