"""Proxy Shield: presence sandwich, face replay, proxy lockout, confidence score."""

from __future__ import annotations

from datetime import UTC, datetime, timedelta

from fastapi.testclient import TestClient

from tests.conftest import Clock, World, headers, near, vector
from tests.test_api import challenge, error_code, reading, submit


def test_beacon_must_be_heard_again_after_the_face_scan(client: TestClient, world: World) -> None:
    staff, device, base = world.ready_staff()
    beacon = world.beacon(rssi_threshold=-80)

    # Token from before the face scan (3 windows ≈ 90 s old): the phone left.
    ch = challenge(client, staff, device, beacon).json()
    r = submit(
        client, staff, device, beacon, ch, near(base, 1), beacon=reading(beacon, windows_ago=3)
    )
    assert r.status_code == 422 and error_code(r) == "PRESENCE_LOST"

    # Fresh token but a weak signal while holding the phone up: accepted
    # (proximity was already proven at the challenge).
    ch = challenge(client, staff, device, beacon).json()
    r = submit(client, staff, device, beacon, ch, near(base, 2), beacon=reading(beacon, rssi=-95))
    assert r.status_code == 200, r.text


def test_copied_face_signature_is_rejected(client: TestClient, world: World, clock: Clock) -> None:
    clock.set_local(9, 0)
    staff, device, base = world.ready_staff()
    beacon = world.beacon()
    scan = near(base, 10)

    ch = challenge(client, staff, device, beacon).json()
    assert submit(client, staff, device, beacon, ch, scan).status_code == 200

    # Same signature replayed at check-out (tiny float noise does not help).
    clock.set_local(17, 0)
    replay = [v * 1.0000001 for v in scan]
    ch = challenge(client, staff, device, beacon, action="check_out").json()
    r = submit(client, staff, device, beacon, ch, replay)
    assert r.status_code == 422 and error_code(r) == "FACE_REPLAY"

    # Replaying an enrollment sample is caught too.
    enrolled = world.db.rows("face_templates")[0]["embeddings"][0]
    ch = challenge(client, staff, device, beacon, action="check_out").json()
    r = submit(client, staff, device, beacon, ch, enrolled)
    assert error_code(r) == "FACE_REPLAY"

    # A genuine new scan still works.
    ch = challenge(client, staff, device, beacon, action="check_out").json()
    assert submit(client, staff, device, beacon, ch, near(base, 11)).status_code == 200


def test_repeated_wrong_faces_lock_check_in(client: TestClient, world: World, clock: Clock) -> None:
    clock.now = datetime.now(UTC)
    staff, device, _base = world.ready_staff()
    beacon = world.beacon()

    for i in range(3):
        ch = challenge(client, staff, device, beacon).json()
        r = submit(client, staff, device, beacon, ch, vector(900 + i))
        assert error_code(r) == "FACE_MISMATCH"

    r = challenge(client, staff, device, beacon)
    assert r.status_code == 422 and error_code(r) == "PROXY_LOCKED"
    assert "Try again after" in r.json()["error"]["message"]
    codes = [a["reason_code"] for a in world.db.rows("attendance_attempts")]
    assert codes.count("PROXY_LOCKED") == 1  # visible to the admin as an alert

    # The lock lifts once the failures leave the 30-minute window.
    clock.now = datetime.now(UTC) + timedelta(minutes=31)
    ch = challenge(client, staff, device, beacon)
    assert ch.status_code == 200, ch.text


def test_confidence_score_for_staff_and_admin(client: TestClient, world: World) -> None:
    staff, device, base = world.ready_staff()
    beacon = world.beacon()
    ch = challenge(client, staff, device, beacon).json()
    body = submit(client, staff, device, beacon, ch, near(base, 20)).json()
    trust = body["verification"]["confidence"]
    assert 0 <= trust <= 100 and trust >= 80
    assert body["verification"]["confidence_level"] == "high"

    admin = world.staff("Admin One", role="admin")
    roster = client.get("/api/v1/admin/attendance", headers=headers(admin)).json()
    row = next(r for r in roster["rows"] if r["staff"]["id"] == staff["id"])
    assert 60 <= row["confidence"] <= 100
    not_marked = [r for r in roster["rows"] if r["status"] == "not_marked"]
    assert all(r["confidence"] is None for r in not_marked)
