"""Presence confidence: one 0-100 number summarising how strong a check-in was.

Every accepted check-in already passed all hard checks. This score shows *how
comfortably* it passed, so an admin can spot borderline ones at a glance
(weak face match, faint beacon, no GPS fix, flags).
"""

from __future__ import annotations

from collections.abc import Sequence

# Weights add up to 100.
_FACE, _SIGNAL, _FRESH, _LOCATION, _DEVICE = 40, 20, 10, 20, 10
_FLAG_PENALTY = 5


def _clamp(x: float) -> float:
    return max(0.0, min(1.0, x))


def presence_confidence(
    *,
    face_score: float | None,
    face_threshold: float,
    rssi: int | None,
    rssi_threshold: int | None,
    distance_m: float | None,
    radius_m: float | None,
    accuracy_m: float | None,
    flags: Sequence[str] = (),
    token_age: int | None = None,
) -> int:
    """Weighted score of the evidence behind one check-in (0-100)."""
    # Face: just at the threshold → 0.5, threshold + 0.25 or more → 1.0.
    face = _clamp(0.5 + (face_score - face_threshold) * 2) if face_score is not None else 0.0
    # Beacon signal: at the threshold → 0.4, 20 dB above it → 1.0.
    if rssi is None or rssi_threshold is None:
        signal = 0.5
    else:
        signal = _clamp(0.4 + (rssi - rssi_threshold) * 0.03)
    # Beacon freshness after the face scan (0 = current 30 s window).
    fresh = {0: 1.0, 1: 0.8, 2: 0.6}.get(token_age, 0.4) if token_age is not None else 0.8
    # Location: inside the campus radius with a good fix scores best.
    if distance_m is None:
        location = 0.3  # no GPS fix, or campus location not configured
    elif radius_m is not None and distance_m <= radius_m:
        location = 1.0 if accuracy_m is None or accuracy_m <= 50 else 0.8
    else:
        location = 0.1
    device = 1.0  # bound, physical phone (otherwise the check-in is rejected)

    score = _FACE * face + _SIGNAL * signal + _FRESH * fresh + _LOCATION * location
    score += _DEVICE * device
    score -= _FLAG_PENALTY * len(flags)
    return round(max(0.0, min(100.0, score)))


def level(score: int) -> str:
    """High / medium / low label for the UI."""
    return "high" if score >= 80 else "medium" if score >= 60 else "low"
