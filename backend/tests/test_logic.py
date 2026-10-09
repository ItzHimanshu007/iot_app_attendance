"""Pure-logic tests: beacon tokens, face maths, geofence, liveness, time."""

from __future__ import annotations

from datetime import UTC, datetime, time
from zoneinfo import ZoneInfo

import pytest
from app.core.exceptions import ValidationError
from app.core.timeutil import is_late, parse_time
from app.services import beacon_token, face_matching, geofence, liveness

from tests.conftest import near, vector

BEACON_ID = "43905a99-a513-5a9d-8cb5-e109b98166bb"
SECRET = "a" * 64


# ── Beacon tokens ─────────────────────────────────────────────────────────────


def test_token_known_vector() -> None:
    """Fixed vector shared with the firmware (see firmware/README.md)."""
    assert beacon_token.compute_token(SECRET, BEACON_ID, 58_000_000) == "37a4820d05333aa1"
    # Beacon IDs are case-insensitive.
    assert beacon_token.compute_token(SECRET, BEACON_ID.upper(), 58_000_000) == "37a4820d05333aa1"


def test_token_windows() -> None:
    now = 1_760_000_000.0
    window = beacon_token.current_window(30, now)
    current = beacon_token.compute_token(SECRET, BEACON_ID, window)
    previous = beacon_token.compute_token(SECRET, BEACON_ID, window - 1)
    old = beacon_token.compute_token(SECRET, BEACON_ID, window - 3)
    nxt = beacon_token.compute_token(SECRET, BEACON_ID, window + 1)
    kw = {"window_seconds": 30, "past_windows": 1, "future_windows": 1, "now": now}
    assert beacon_token.verify_token(current, SECRET, BEACON_ID, **kw) == 0
    assert beacon_token.verify_token(previous.upper(), SECRET, BEACON_ID, **kw) == 1
    assert beacon_token.verify_token(nxt, SECRET, BEACON_ID, **kw) == -1
    assert beacon_token.verify_token(old, SECRET, BEACON_ID, **kw) is None
    assert beacon_token.verify_token(current, "b" * 64, BEACON_ID, **kw) is None
    assert beacon_token.verify_token("not-a-token", SECRET, BEACON_ID, **kw) is None


def test_new_secret_is_random_hex() -> None:
    a, b = beacon_token.new_secret(), beacon_token.new_secret()
    assert a != b and len(a) == 64 and int(a, 16) >= 0


# ── Face maths ────────────────────────────────────────────────────────────────


def test_same_person_scores_high_and_stranger_low() -> None:
    base = vector(1)
    samples = [face_matching.normalize(near(base, i)) for i in range(3)]
    same = face_matching.normalize(near(base, 99))
    stranger = face_matching.normalize(vector(2))
    assert face_matching.best_match(same, samples) > 0.8
    assert face_matching.best_match(stranger, samples) < 0.3
    assert face_matching.min_pairwise_similarity(samples) > 0.8


def test_normalize_rejects_bad_vectors() -> None:
    with pytest.raises(ValidationError):
        face_matching.normalize([0.0] * 192)
    with pytest.raises(ValidationError):
        face_matching.normalize([float("nan")] * 192)


def test_dimension_mismatch() -> None:
    with pytest.raises(ValidationError):
        face_matching.cosine([1.0, 0.0], [1.0, 0.0, 0.0])


# ── Geofence ──────────────────────────────────────────────────────────────────

CAMPUS = {
    "latitude": 26.8226,
    "longitude": 75.8644,
    "radius_m": 500,
    "max_location_accuracy_m": 150,
}


def test_haversine_one_km() -> None:
    # ~0.009 degrees latitude ≈ 1 km
    assert 990 < geofence.haversine_m(26.0, 75.0, 26.009, 75.0) < 1010


def test_geofence_inside_and_outside() -> None:
    inside = {"latitude": 26.8230, "longitude": 75.8650, "accuracy_m": 20, "is_mocked": False}
    far = {"latitude": 26.90, "longitude": 75.80, "accuracy_m": 20, "is_mocked": False}

    ok = geofence.evaluate({**CAMPUS, "geofence_mode": "enforce"}, inside)
    assert ok.reject_code is None and ok.distance_m is not None and ok.distance_m < 100

    flagged = geofence.evaluate({**CAMPUS, "geofence_mode": "flag"}, far)
    assert flagged.reject_code is None and "outside_geofence" in flagged.flags

    rejected = geofence.evaluate({**CAMPUS, "geofence_mode": "enforce"}, far)
    assert rejected.reject_code == "OUTSIDE_CAMPUS"


def test_geofence_mock_and_missing() -> None:
    mocked = {"latitude": 26.8226, "longitude": 75.8644, "accuracy_m": 5, "is_mocked": True}
    assert geofence.evaluate({**CAMPUS, "geofence_mode": "flag"}, mocked).reject_code == (
        "MOCK_LOCATION"
    )
    assert geofence.evaluate({**CAMPUS, "geofence_mode": "enforce"}, None).reject_code == (
        "LOCATION_REQUIRED"
    )
    assert "no_location" in geofence.evaluate({**CAMPUS, "geofence_mode": "flag"}, None).flags
    assert geofence.evaluate({**CAMPUS, "geofence_mode": "off"}, mocked).reject_code is None


# ── Liveness ──────────────────────────────────────────────────────────────────


def test_pick_steps_distinct_and_known() -> None:
    for _ in range(50):
        steps = liveness.pick_steps(2)
        assert len(steps) == 2 and len(set(steps)) == 2
        assert set(steps) <= set(liveness.ALL_STEPS)
    assert len(liveness.pick_steps(10)) == len(liveness.ALL_STEPS)


# ── Time ──────────────────────────────────────────────────────────────────────


def test_is_late_uses_campus_timezone() -> None:
    tz = ZoneInfo("Asia/Kolkata")
    start = parse_time("09:00:00", time(9, 0))
    on_time = datetime(2026, 10, 9, 3, 40, tzinfo=UTC)  # 09:10 IST
    late = datetime(2026, 10, 9, 3, 50, tzinfo=UTC)  # 09:20 IST
    assert not is_late(on_time, tz, start, 15)
    assert is_late(late, tz, start, 15)
