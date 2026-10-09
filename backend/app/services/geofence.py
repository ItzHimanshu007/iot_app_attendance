"""Campus geofence check (great-circle distance from the campus centre)."""

from __future__ import annotations

import math
from dataclasses import dataclass, field
from typing import Any

EARTH_RADIUS_M = 6_371_000.0


def haversine_m(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """Distance in metres between two lat/lng points."""
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp = p2 - p1
    dl = math.radians(lon2 - lon1)
    a = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * EARTH_RADIUS_M * math.asin(math.sqrt(a))


@dataclass
class GeofenceResult:
    """Outcome of a geofence evaluation."""

    mode: str
    distance_m: float | None = None
    flags: list[str] = field(default_factory=list)
    reject_code: str | None = None
    reject_message: str | None = None


def evaluate(campus: dict[str, Any], location: dict[str, Any] | None) -> GeofenceResult:
    """Evaluate a phone location against the campus settings.

    Modes (``campus_settings.geofence_mode``):
        off     — location ignored.
        flag    — outside / inaccurate / missing is recorded as a flag.
        enforce — outside or missing location is rejected.

    A mocked (fake-GPS) location is rejected in both ``flag`` and ``enforce``.
    """
    mode = campus.get("geofence_mode") or "flag"
    result = GeofenceResult(mode=mode)
    if mode == "off":
        return result

    lat, lng = campus.get("latitude"), campus.get("longitude")
    if lat is None or lng is None:
        result.flags.append("campus_location_not_configured")
        return result

    if not location:
        if mode == "enforce":
            result.reject_code = "LOCATION_REQUIRED"
            result.reject_message = "Location is required. Turn on GPS and try again."
        else:
            result.flags.append("no_location")
        return result

    if location.get("is_mocked"):
        result.reject_code = "MOCK_LOCATION"
        result.reject_message = "A fake-GPS / mock location app was detected."
        return result

    distance = haversine_m(float(lat), float(lng), location["latitude"], location["longitude"])
    result.distance_m = round(distance, 1)
    radius = float(campus.get("radius_m") or 500)
    accuracy = location.get("accuracy_m")
    max_accuracy = float(campus.get("max_location_accuracy_m") or 150)

    if accuracy is not None and accuracy > max_accuracy:
        result.flags.append("low_gps_accuracy")

    # Give the benefit of the doubt up to the reported accuracy.
    effective = distance - min(float(accuracy or 0), max_accuracy)
    if effective > radius:
        if mode == "enforce":
            result.reject_code = "OUTSIDE_CAMPUS"
            result.reject_message = (
                f"You appear to be {int(distance)} m from campus (allowed {int(radius)} m)."
            )
        else:
            result.flags.append("outside_geofence")
    return result
