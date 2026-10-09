"""Attendance verification engine.

Two calls per check-in / check-out:

1. ``create_challenge`` — the phone proves it can hear a campus beacon right
   now (rotating HMAC token + RSSI), from the bound phone, for an approved
   staff member who is allowed to perform this action today. The server
   answers with a one-time challenge and random liveness steps.

2. ``submit`` — the phone sends the face signature captured live after the
   liveness steps, a fresh beacon reading and a GPS fix. The challenge is
   consumed first (so a failed face match cannot be retried with the same
   challenge), then every check runs in order. Only if all pass is the
   attendance row written.

Every failure is recorded in ``attendance_attempts`` with its reason code.
"""

from __future__ import annotations

import contextlib
from datetime import datetime, time, timedelta
from typing import Any

from app.core.config import get_settings
from app.core.exceptions import ConflictError, ValidationError, VerificationError
from app.core.timeutil import campus_zone, is_late, local_today, now_utc, parse_time, parse_ts
from app.repositories.attendance_repo import AttendanceRepository
from app.repositories.beacon_repo import BeaconRepository
from app.repositories.challenge_repo import ChallengeRepository
from app.schemas.requests import BeaconReading, ChallengeRequest, SubmitRequest
from app.security.auth import CurrentStaff
from app.services import campus_service, device_service, face_service, geofence
from app.services.attempt_service import record_attempt
from app.services.beacon_token import verify_token
from app.services.liveness import pick_steps

_attendance = AttendanceRepository()
_beacons = BeaconRepository()
_challenges = ChallengeRepository()

WEAK_MATCH_MARGIN = 0.05
DEFAULT_WORK_START = time(9, 0)

_PUBLIC_RECORD_FIELDS = (
    "id",
    "staff_id",
    "attendance_date",
    "status",
    "check_in_at",
    "check_out_at",
    "check_in_beacon_id",
    "check_out_beacon_id",
    "check_in_face_score",
    "check_out_face_score",
    "check_in_distance_m",
    "check_out_distance_m",
    "flags",
    "is_manual",
    "manual_reason",
)


def public_record(row: dict[str, Any] | None) -> dict[str, Any] | None:
    """Attendance fields safe to return."""
    if row is None:
        return None
    return {k: row.get(k) for k in _PUBLIC_RECORD_FIELDS}


# ── Shared checks ─────────────────────────────────────────────────────────────


def _verify_beacon(reading: BeaconReading, past_windows: int) -> dict[str, Any]:
    settings = get_settings()
    beacon = _beacons.get_by_id(str(reading.beacon_id))
    if beacon is None or not beacon.get("is_active", False):
        raise VerificationError("This beacon is not registered on campus.", "BEACON_UNKNOWN")
    if reading.rssi < int(beacon.get("rssi_threshold", -85)):
        raise VerificationError(
            "The beacon signal is too weak. Move closer to the beacon.", "BEACON_TOO_FAR"
        )
    age = verify_token(
        reading.token,
        beacon["secret"],
        beacon["id"],
        window_seconds=settings.beacon_window_seconds,
        past_windows=past_windows,
        future_windows=settings.beacon_future_windows,
    )
    if age is None:
        raise VerificationError(
            "The beacon code is invalid or expired. Stay near the beacon and try again.",
            "BEACON_TOKEN_INVALID",
        )
    return beacon


def _check_action_allowed(action: str, record: dict[str, Any] | None) -> None:
    if record and record.get("is_manual") and record.get("status") in ("absent", "on_leave"):
        label = "on leave" if record["status"] == "on_leave" else "absent"
        raise VerificationError(f"An admin has marked you {label} today.", "DAY_LOCKED")
    if action == "check_in":
        if record and record.get("check_in_at"):
            raise VerificationError("You have already checked in today.", "ALREADY_CHECKED_IN")
        return
    if not record or not record.get("check_in_at"):
        raise VerificationError("You have not checked in today.", "NOT_CHECKED_IN")
    if record.get("check_out_at"):
        raise VerificationError("You have already checked out today.", "ALREADY_CHECKED_OUT")


def _check_physical(is_physical_device: bool) -> None:
    if get_settings().block_emulators and not is_physical_device:
        raise VerificationError("Emulators are not allowed.", "EMULATOR_NOT_ALLOWED")


def _context() -> tuple[dict[str, Any], Any, datetime, str]:
    campus = campus_service.get_campus()
    tz = campus_zone(campus.get("timezone"))
    now = now_utc()
    return campus, tz, now, local_today(tz, now).isoformat()


# ── Step 1: challenge ─────────────────────────────────────────────────────────


def create_challenge(staff: CurrentStaff, req: ChallengeRequest, ip: str | None) -> dict[str, Any]:
    """Validate proximity/device/state and issue a one-time challenge."""
    settings = get_settings()
    _campus, _tz, now, today = _context()
    log = {
        "beacon_id": str(req.beacon.beacon_id),
        "rssi": req.beacon.rssi,
        "device_fingerprint": req.device_fingerprint,
        "ip_address": ip,
    }
    try:
        _check_physical(req.is_physical_device)
        device_service.require_bound_device(staff.id, req.device_fingerprint)
        face_service.require_approved(staff.id)
        beacon = _verify_beacon(req.beacon, settings.beacon_challenge_past_windows)
        _check_action_allowed(req.action, _attendance.get_for_day(staff.id, today))

        steps = pick_steps(settings.liveness_steps_count)
        expires = now + timedelta(seconds=settings.challenge_ttl_seconds)
        row = _challenges.insert(
            {
                "staff_id": staff.id,
                "action": req.action,
                "beacon_id": beacon["id"],
                "liveness_steps": steps,
                "device_fingerprint": req.device_fingerprint,
                "expires_at": expires.isoformat(),
            }
        )
    except VerificationError as e:
        record_attempt(staff.id, f"challenge_{req.action}", False, e.code, e.message, **log)
        raise

    return {
        "challenge_id": row["id"],
        "action": req.action,
        "liveness_steps": steps,
        "expires_at": expires.isoformat(),
        "ttl_seconds": settings.challenge_ttl_seconds,
        "beacon": {"id": beacon["id"], "name": beacon.get("name")},
    }


# ── Step 2: submit ────────────────────────────────────────────────────────────


def submit(staff: CurrentStaff, req: SubmitRequest, ip: str | None) -> dict[str, Any]:
    """Run every check and write the attendance record."""
    settings = get_settings()
    campus, tz, now, today = _context()
    action = "unknown"
    log: dict[str, Any] = {
        "beacon_id": str(req.beacon.beacon_id),
        "rssi": req.beacon.rssi,
        "device_fingerprint": req.device_fingerprint,
        "ip_address": ip,
    }
    if req.location:
        log.update(
            latitude=req.location.latitude,
            longitude=req.location.longitude,
            accuracy_m=req.location.accuracy_m,
        )

    try:
        # 1. Challenge: exists, mine, unused, fresh → consume it atomically.
        challenge = _challenges.get_by_id(str(req.challenge_id))
        if challenge is None or challenge.get("staff_id") != staff.id:
            raise VerificationError("Unknown challenge. Please start again.", "CHALLENGE_INVALID")
        action = challenge["action"]
        if challenge.get("consumed_at"):
            raise VerificationError(
                "This verification was already used. Please start again.", "CHALLENGE_USED"
            )
        expires_at = parse_ts(challenge["expires_at"])
        if expires_at is None or expires_at < now:
            raise VerificationError(
                "Verification took too long. Please start again.", "CHALLENGE_EXPIRED"
            )
        if _challenges.consume(challenge["id"], staff.id, now.isoformat()) is None:
            raise VerificationError(
                "This verification was already used. Please start again.", "CHALLENGE_USED"
            )

        # 2. Same physical phone as the challenge and as the bound device.
        _check_physical(req.is_physical_device)
        if req.device_fingerprint != challenge["device_fingerprint"]:
            raise VerificationError("Phone changed during verification.", "DEVICE_MISMATCH")
        device = device_service.require_bound_device(staff.id, req.device_fingerprint)

        # 3. Still near the same beacon.
        if str(req.beacon.beacon_id) != str(challenge["beacon_id"]):
            raise VerificationError(
                "Beacon changed during verification. Please start again.", "BEACON_MISMATCH"
            )
        beacon = _verify_beacon(req.beacon, settings.beacon_submit_past_windows)

        # 4. Liveness: the exact random steps, in order.
        expected_steps = [str(s) for s in challenge.get("liveness_steps") or []]
        if [s.strip().lower() for s in req.completed_steps] != expected_steps:
            raise VerificationError(
                "Liveness check failed. Follow the on-screen instructions.", "LIVENESS_FAILED"
            )

        # 5. Face.
        score = face_service.match(staff.id, req.embedding)
        log["face_score"] = round(score, 4)
        threshold = float(campus["face_match_threshold"])
        if score < threshold:
            raise VerificationError("Face did not match your enrolled face.", "FACE_MISMATCH")

        # 6. Campus geofence.
        geo = geofence.evaluate(campus, req.location.model_dump() if req.location else None)
        if geo.reject_code:
            raise VerificationError(geo.reject_message or "Location rejected", geo.reject_code)
        flags = list(geo.flags)
        if score < threshold + WEAK_MATCH_MARGIN:
            flags.append("weak_face_match")

        # 7. State + write.
        record = _attendance.get_for_day(staff.id, today)
        _check_action_allowed(action, record)
        saved = _write(
            action, staff, record, today, now, tz, campus, beacon, req, score, geo, flags
        )
    except VerificationError as e:
        record_attempt(staff.id, f"submit_{action}", False, e.code, e.message, **log)
        raise

    device_service.touch(device["id"])
    with contextlib.suppress(Exception):
        _beacons.update(beacon["id"], {"last_used_at": now.isoformat()})
    record_attempt(staff.id, f"submit_{action}", True, None, None, **log)

    return {
        "action": action,
        "attendance": public_record(saved),
        "verification": {
            "face_score": round(score, 4),
            "face_threshold": threshold,
            "beacon": {"id": beacon["id"], "name": beacon.get("name")},
            "distance_m": geo.distance_m,
            "geofence_mode": geo.mode,
            "flags": flags,
        },
    }


def _write(
    action: str,
    staff: CurrentStaff,
    record: dict[str, Any] | None,
    today: str,
    now: datetime,
    tz: Any,
    campus: dict[str, Any],
    beacon: dict[str, Any],
    req: SubmitRequest,
    score: float,
    geo: geofence.GeofenceResult,
    flags: list[str],
) -> dict[str, Any]:
    if action == "check_in":
        late = is_late(
            now,
            tz,
            parse_time(campus.get("work_start_time"), DEFAULT_WORK_START),
            int(campus.get("late_grace_minutes") or 0),
        )
        data: dict[str, Any] = {
            "status": "late" if late else "present",
            "check_in_at": now.isoformat(),
            "check_in_beacon_id": beacon["id"],
            "check_in_rssi": req.beacon.rssi,
            "check_in_face_score": round(score, 4),
            "check_in_latitude": req.location.latitude if req.location else None,
            "check_in_longitude": req.location.longitude if req.location else None,
            "check_in_accuracy_m": req.location.accuracy_m if req.location else None,
            "check_in_distance_m": geo.distance_m,
            "device_fingerprint": req.device_fingerprint,
            "flags": flags,
        }
        if record:
            return _attendance.update(record["id"], data)
        try:
            return _attendance.insert({"staff_id": staff.id, "attendance_date": today, **data})
        except ConflictError as e:
            raise VerificationError(
                "You have already checked in today.", "ALREADY_CHECKED_IN"
            ) from e

    assert record is not None  # guaranteed by _check_action_allowed
    merged_flags = sorted(set(record.get("flags") or []) | {f"checkout_{f}" for f in flags})
    return _attendance.update(
        record["id"],
        {
            "check_out_at": now.isoformat(),
            "check_out_beacon_id": beacon["id"],
            "check_out_rssi": req.beacon.rssi,
            "check_out_face_score": round(score, 4),
            "check_out_distance_m": geo.distance_m,
            "flags": merged_flags,
        },
    )


# ── Reads ─────────────────────────────────────────────────────────────────────


def today(staff: CurrentStaff) -> dict[str, Any]:
    """Today's record plus the campus rules the app displays."""
    campus, _tz, _now, day = _context()
    return {
        "date": day,
        "attendance": public_record(_attendance.get_for_day(staff.id, day)),
        "campus": {
            "campus_name": campus.get("campus_name"),
            "timezone": campus.get("timezone"),
            "work_start_time": str(campus.get("work_start_time")),
            "late_grace_minutes": campus.get("late_grace_minutes"),
        },
    }


def history(
    staff: CurrentStaff, date_from: str | None, date_to: str | None
) -> list[dict[str, Any]]:
    """Own records in a date range (default: last 30 days)."""
    _campus, tz, now, day = _context()
    end = date_to or day
    start = date_from or (local_today(tz, now) - timedelta(days=30)).isoformat()
    if start > end:
        raise ValidationError("'from' must be before 'to'", "INVALID_RANGE")
    rows = _attendance.list_for_staff(staff.id, start, end)
    return [r for r in (public_record(row) for row in rows) if r is not None]
