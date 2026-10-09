"""Attendance service — the core validation engine.

Validates and records attendance through an 8-step validation pipeline:

  Step 1: JWT already validated (by dependency)
  Step 2: Active session exists
  Step 3: Session not expired
  Step 4: Student is enrolled in the session's subject
  Step 5: Student has a registered device
  Step 6: Device fingerprint matches
  Step 7: No duplicate attendance
  Step 8: Beacon token is valid

Only after ALL validations pass does the record get inserted.
Any failure returns a descriptive, typed error.
"""

from __future__ import annotations

import time
import uuid
from datetime import UTC, datetime
from typing import Any

from app.core.config import get_settings
from app.core.exceptions import (
    AuthorizationError,
    ConflictError,
    DuplicateAttendanceError,
    EnrollmentRequiredError,
    InvalidTokenError,
    NotFoundError,
    SessionExpiredError,
    SessionNotActiveError,
)
from app.core.logging import get_logger
from app.repositories.attendance_repo import AttendanceRepository
from app.repositories.base import RepositoryError
from app.repositories.enrollment_repo import EnrollmentRepository
from app.repositories.manual_attendance_audit_repo import ManualAttendanceAuditRepository
from app.repositories.session_repo import SessionRepository
from app.repositories.subject_repo import SubjectRepository
from app.repositories.user_repo import UserRepository
from app.services import notification_service
from app.services.device_service import validate_device
from app.services.session_service import _resolve_subject_id
from app.services.token_service import (
    FIXED_TOKEN_MODE,
    verify_session_token,
    verify_stored_token,
)

logger = get_logger(__name__)

_user_repo = UserRepository()
_audit_repo = ManualAttendanceAuditRepository()

_session_repo = SessionRepository()
_attendance_repo = AttendanceRepository()
_enrollment_repo = EnrollmentRepository()
_subject_repo = SubjectRepository()


def submit_attendance(
    student_id: str,
    session_id: str,
    beacon_token: str,
    device_fingerprint: str,
    biometric_verified: bool = False,
    ble_rssi: int | None = None,
    ip_address: str | None = None,
) -> dict[str, Any]:
    """Execute the full 8-step attendance validation pipeline.

    Args:
        student_id: Authenticated user's ID (from JWT).
        session_id: The attendance session to mark.
        beacon_token: BLE token received from passive scan.
        device_fingerprint: Device hardware hash from Flutter app.
        biometric_verified: Whether Android biometric auth passed.
        ble_rssi: BLE signal strength in dBm (optional).
        ip_address: Client IP for audit (optional).

    Returns:
        The created attendance record.

    Raises:
        NotFoundError: Session not found.
        SessionNotActiveError: Session status is not 'active'.
        SessionExpiredError: Current time is past session.expires_at.
        EnrollmentRequiredError: Student not enrolled in the subject.
        DeviceNotRegisteredError: No active device for student.
        DeviceMismatchError: Fingerprint doesn't match registered device.
        DuplicateAttendanceError: Student already marked attendance.
        InvalidTokenError: Beacon token doesn't match current time window.
    """
    # ── STEP 2: Validate session exists ───────────────────────────────────
    session = _session_repo.get_by_id(session_id)
    if session is None:
        raise NotFoundError("AttendanceSession", session_id)

    # ── STEP 3: Validate session is active and not expired ────────────────
    if session["status"] != "active":
        raise SessionNotActiveError(session_id)

    now = datetime.now(UTC)
    expires_at = datetime.fromisoformat(session["expires_at"])
    if now >= expires_at:
        raise SessionExpiredError(session_id)

    # ── STEP 4: Validate enrollment ───────────────────────────────────────
    subject_id = session["subject_id"]
    if get_settings().enforce_subject_enrollment and not _enrollment_repo.is_enrolled(
        student_id, subject_id
    ):
        raise EnrollmentRequiredError(student_id, subject_id)

    # ── STEP 5 & 6: Validate device (registered + fingerprint match) ─────
    validate_device(student_id, device_fingerprint)

    # ── STEP 7: Check duplicate attendance ────────────────────────────────
    if _attendance_repo.has_marked(session_id, student_id):
        raise DuplicateAttendanceError(session_id, student_id)

    # ── STEP 8: Validate beacon token ────────────────────────────────────
    classroom_id = session["classroom_id"]

    if FIXED_TOKEN_MODE:
        # Development mode — validate against the pre-stored session token.
        # Token was generated once at session creation and never rotated.
        # To re-enable HMAC rotation: set FIXED_TOKEN_MODE=False in token_service.py.
        stored_token = session.get("current_token")
        token_valid = verify_stored_token(beacon_token, stored_token)
    else:
        # Production mode — recalculate HMAC for current/previous time window.
        token_valid = verify_session_token(beacon_token, classroom_id)

    if not token_valid:
        raise InvalidTokenError()

    # ── All validations passed — insert record ────────────────────────────

    # Determine late status (if more than 15 minutes after session start)
    started_at = datetime.fromisoformat(session["started_at"])
    is_late = (now - started_at).total_seconds() > 900  # 15 minutes

    record_data: dict[str, Any] = {
        "session_id": session_id,
        "student_id": student_id,
        "beacon_token": beacon_token,
        "ble_rssi": ble_rssi,
        "biometric_verified": biometric_verified,
        "device_fingerprint": device_fingerprint,
        "status": "late" if is_late else "present",
        "verification_method": "ble_biometric" if biometric_verified else "ble_only",
        "marked_at": now.isoformat(),
        "verified_at": now.isoformat(),
        "ip_address": ip_address,
    }

    record = _attendance_repo.insert(record_data)
    logger.info(
        "Attendance recorded",
        session_id=session_id,
        student_id=student_id,
        status=record_data["status"],
    )

    # Update denormalized count on the session
    try:
        _session_repo.increment_present(session_id, session["total_present"])
    except Exception as e:
        logger.error("Failed to increment present count", error=str(e))

    # Send confirmation notification
    try:
        subject = _subject_repo.get_by_id(subject_id)
        subject_name = subject["name"] if subject else "Unknown Subject"
        notification_service.send_attendance_confirmation(student_id, session_id, subject_name)
    except Exception as e:
        logger.error("Failed to send attendance notification", error=str(e))

    student_profile = _user_repo.get_by_id(student_id)
    return _map_attendance_record({**record, "student": student_profile})


def _map_attendance_record(record: dict[str, Any]) -> dict[str, Any]:
    """Map DB attendance record and joined student profile to DTO fields."""
    student = record.get("student") or {}
    status = record.get("status")
    verification_method = record.get("verification_method")

    return {
        **record,
        "student_name": student.get("full_name"),
        "roll_number": student.get("student_id_number"),
        "attendance_status": status,
        "is_manual": verification_method == "manual",
    }


# ── Query functions ───────────────────────────────────────────────────────────


def list_session_attendance(session_id: str, limit: int = 200) -> list[dict[str, Any]]:
    """Get all attendance records for a session.

    Raises:
        NotFoundError: Session not found.
    """
    session = _session_repo.get_by_id(session_id)
    if session is None:
        raise NotFoundError("AttendanceSession", session_id)
    return [_map_attendance_record(r) for r in _attendance_repo.list_by_session(session_id, limit=limit)]


def list_student_attendance(student_id: str, limit: int = 100) -> list[dict[str, Any]]:
    """Get attendance history for a student."""
    return [_map_attendance_record(r) for r in _attendance_repo.list_by_student(student_id, limit=limit)]


def get_attendance_record(record_id: str) -> dict[str, Any]:
    """Get a single attendance record.

    Raises:
        NotFoundError: Record not found.
    """
    record = _attendance_repo.get_by_id_with_profile(record_id)
    if record is None:
        raise NotFoundError("AttendanceRecord", record_id)
    return _map_attendance_record(record)


def revoke_attendance(record_id: str, reason: str) -> dict[str, Any]:
    """Revoke an attendance record (admin/teacher action).

    Raises:
        NotFoundError: Record not found.
    """
    record = _attendance_repo.get_by_id_with_profile(record_id)
    if record is None:
        raise NotFoundError("AttendanceRecord", record_id)

    updated = _attendance_repo.revoke(record_id, reason)
    logger.info(
        "Attendance revoked",
        record_id=record_id,
        reason=reason,
    )
    return _map_attendance_record({**updated, "student": record.get("student")})



def _compensate_attendance_write(
    record_id: str | None,
    orig_record: dict[str, Any] | None,
) -> None:
    """Revert database changes to the attendance_records table."""
    logger.warning(
        "Audit log insertion failed. Reverting manual attendance record changes.",
        record_id=record_id,
        had_original=orig_record is not None,
    )
    try:
        if orig_record:
            # Check if record exists
            exists = _attendance_repo.get_by_id(orig_record["id"])
            if exists:
                # Revert update
                _attendance_repo.update(
                    orig_record["id"],
                    {
                        "status": orig_record["status"],
                        "verification_method": orig_record["verification_method"],
                        "marked_at": orig_record["marked_at"],
                        "verified_at": orig_record["verified_at"],
                    },
                )
            else:
                # Revert delete (insert it back)
                clean_orig = {k: v for k, v in orig_record.items() if k not in ("student", "session")}
                _attendance_repo.insert(clean_orig)
        elif record_id:
            # Revert insert (delete)
            _attendance_repo.delete(record_id)
    except Exception as rollback_err:
        logger.critical(
            "Failed to rollback/compensate manual attendance write!",
            error=str(rollback_err),
        )


def _calculate_roster_summary(session_id: str, subject_id: str | None) -> dict[str, int]:
    """Helper to calculate total expected students, present, and absent counts."""
    # Fetch session attendance records
    attendance_records = _attendance_repo.list_by_session(session_id, limit=1000)

    if not subject_id:
        # For custom sessions, calculate statistics based strictly on actual attendance records
        present = sum(1 for r in attendance_records if r.get("status") in ("present", "late"))
        absent = sum(1 for r in attendance_records if r.get("status") in ("absent", "revoked"))
        return {
            "total_students": present + absent,
            "present": present,
            "absent": absent,
        }


    # Fetch active enrollment profiles for subject
    enrollments = _enrollment_repo.get_subject_students_with_profiles(subject_id)
    active_students = [
        item["student"]
        for item in enrollments
        if item.get("student") and item["student"].get("is_active", False)
    ]
    total_students = len(active_students)

    record_map = {r["student_id"]: r for r in attendance_records}

    present = 0
    absent = 0
    for s in active_students:
        s_id = s["id"]
        rec = record_map.get(s_id)
        if rec and rec.get("status") in ("present", "late"):
            present += 1
        else:
            absent += 1

    return {
        "total_students": total_students,
        "present": present,
        "absent": absent,
    }


def mark_manual_attendance(
    session_id: str,
    student_id: str,
    status: str,
    teacher_id: str,
    user_role: str,
    reason: str | None = None,
) -> dict[str, Any]:
    """Manually mark/change attendance status for a student in a session."""
    start_time = time.perf_counter()
    operation_id = str(uuid.uuid4())

    # 1. Validate session exists
    session = _session_repo.get_by_id(session_id)
    if session is None:
        raise NotFoundError("AttendanceSession", session_id)

    # Validate teacher/admin permission
    if user_role != "admin" and session.get("teacher_id") != teacher_id:
        raise AuthorizationError("You do not have permission to modify this session's attendance")

    # Validate session editability (Only active and completed statuses allowed)
    session_status = session.get("status")
    if session_status not in ("active", "completed"):
        raise ConflictError(f"Cannot manually modify attendance for a '{session_status}' session")

    # 2. Verify student exists
    student = _user_repo.get_by_id(student_id)
    if student is None:
        raise NotFoundError("User", student_id)

    # 3. Resolve subject & check student enrollment
    subject_id = _resolve_subject_id(session, raise_on_error=False)
    if subject_id and not _enrollment_repo.is_enrolled(student_id, subject_id):
        raise ConflictError(f"Student '{student_id}' is not enrolled in subject '{subject_id}'")

    # 4. Fetch current record
    orig_record = _attendance_repo.get_by_session_and_student(session_id, student_id)
    old_status = orig_record.get("status") if orig_record else None

    effective_old_status = old_status if old_status is not None else "absent"

    # 5. Handle Idempotent path
    if effective_old_status == status:
        summary = _calculate_roster_summary(session_id, subject_id)
        duration_ms = (time.perf_counter() - start_time) * 1000.0

        logger.info(
            "Manual attendance marked (idempotent)",
            operation_id=operation_id,
            teacher_id=teacher_id,
            student_id=student_id,
            session_id=session_id,
            previous_status=old_status,
            new_status=status,
            operation="unchanged",
            result="success",
            duration_ms=duration_ms,
        )

        if orig_record:
            rec_id = orig_record["id"]
            v_method = orig_record.get("verification_method", "manual")
            biometric = orig_record.get("biometric_verified", False)
            ble_rssi = orig_record.get("ble_rssi")
            marked_at = orig_record["marked_at"]
            verified_at = orig_record.get("verified_at")
            created_at = orig_record["created_at"]
        else:
            rec_id = "absent-record"
            v_method = "manual"
            biometric = False
            ble_rssi = None
            marked_at = datetime.now(UTC).isoformat()
            verified_at = None
            created_at = datetime.now(UTC).isoformat()

        return {
            "id": rec_id,
            "session_id": session_id,
            "student_id": student_id,
            "status": status,
            "verification_method": v_method,
            "biometric_verified": biometric,
            "ble_rssi": ble_rssi,
            "marked_at": marked_at,
            "verified_at": verified_at,
            "rejection_reason": None,
            "created_at": created_at,
            "operation": "unchanged",
            "operation_id": operation_id,
            "previous_status": old_status,
            "modified_by": teacher_id,
            "modified_at": datetime.now(UTC).isoformat(),
            "summary": summary,
        }

    # 6. Perform modification write
    operation = "updated" if orig_record else "created"
    written_record = None
    try:
        now_str = datetime.now(UTC).isoformat()
        if status == "absent":
            if orig_record:
                # Concurrency check
                last_updated_at = orig_record.get("updated_at")
                if not last_updated_at:
                    last_updated_at = orig_record.get("created_at")
                
                current_rec = _attendance_repo.get_by_id(orig_record["id"])
                if not current_rec:
                    raise ConflictError("Concurrent modification detected. Please reload the roster and try again.")
                current_updated_at = current_rec.get("updated_at") or current_rec.get("created_at")
                if current_updated_at != last_updated_at:
                    raise ConflictError("Concurrent modification detected. Please reload the roster and try again.")
                
                _attendance_repo.delete(orig_record["id"])
                
                written_record = {
                    "id": orig_record["id"],
                    "session_id": session_id,
                    "student_id": student_id,
                    "status": "absent",
                    "verification_method": "manual_override",
                    "biometric_verified": False,
                    "device_fingerprint": "manual",
                    "ble_rssi": None,
                    "ip_address": None,
                    "marked_at": now_str,
                    "verified_at": None,
                    "created_at": orig_record["created_at"],
                }
        else:
            if orig_record:
                # Concurrency check
                last_updated_at = orig_record.get("updated_at")
                if not last_updated_at:
                    last_updated_at = orig_record.get("created_at")

                written_record = _attendance_repo.update_with_concurrency_check(
                    orig_record["id"],
                    {
                        "status": status,
                        "verification_method": "manual_override",
                        "beacon_token": "manual",
                        "ble_rssi": None,
                        "biometric_verified": False,
                        "device_fingerprint": "manual",
                        "ip_address": None,
                        "marked_at": now_str,
                        "verified_at": now_str,
                    },
                    last_updated_at,
                )
            else:
                written_record = _attendance_repo.insert(
                    {
                        "session_id": session_id,
                        "student_id": student_id,
                        "beacon_token": "manual",
                        "ble_rssi": None,
                        "biometric_verified": False,
                        "device_fingerprint": "manual",
                        "status": status,
                        "verification_method": "manual_override",
                        "marked_at": now_str,
                        "verified_at": now_str,
                    }
                )
    except RepositoryError as repo_exc:
        if "update_with_concurrency_check" in str(repo_exc) or "returned no rows" in str(repo_exc) or "delete" in str(repo_exc):
            logger.error(
                "Concurrency conflict: record was modified after reading",
                session_id=session_id,
                student_id=student_id,
            )
            raise ConflictError(
                "Concurrent modification detected. Please reload the roster and try again."
            ) from repo_exc
        logger.error("Failed to write manual attendance record", error=str(repo_exc))
        raise
    except Exception as exc:
        logger.error("Failed to write manual attendance record", error=str(exc))
        raise

    # 7. Write to manual_attendance_audits with transaction compensation
    written_record_id = written_record["id"]
    try:
        _audit_repo.insert(
            {
                "id": str(uuid.uuid4()),
                "teacher_id": teacher_id,
                "student_id": student_id,
                "session_id": session_id,
                "previous_status": old_status,
                "new_status": status,
                "operation": operation,
                "operation_id": operation_id,
                "reason": reason,
            }
        )
    except Exception as audit_exc:
        logger.error(
            "Audit log insertion failed. Initiating compensation rollback.",
            error=str(audit_exc),
        )
        _compensate_attendance_write(written_record_id, orig_record)
        raise

    # 8. Recalculate session total_present
    try:
        new_present_count = _attendance_repo.get_session_present_count(session_id)
        _session_repo.update(session_id, {"total_present": new_present_count})
    except Exception as total_exc:
        logger.error("Failed to update session total_present count", error=str(total_exc))

    # 9. Get final roster summary
    summary = _calculate_roster_summary(session_id, subject_id)
    duration_ms = (time.perf_counter() - start_time) * 1000.0

    # Structured Logging
    logger.info(
        "Manual attendance marked successfully",
        operation_id=operation_id,
        teacher_id=teacher_id,
        student_id=student_id,
        session_id=session_id,
        previous_status=old_status,
        new_status=status,
        operation=operation,
        result="success",
        duration_ms=duration_ms,
    )

    return {
        "id": written_record["id"],
        "session_id": written_record["session_id"],
        "student_id": written_record["student_id"],
        "status": written_record["status"],
        "verification_method": written_record["verification_method"],
        "biometric_verified": written_record["biometric_verified"],
        "ble_rssi": written_record.get("ble_rssi"),
        "marked_at": written_record["marked_at"],
        "verified_at": written_record.get("verified_at"),
        "rejection_reason": written_record.get("rejection_reason"),
        "created_at": written_record["created_at"],
        "student_name": student.get("full_name") if student else None,
        "roll_number": student.get("student_id_number") if student else None,
        "attendance_status": written_record["status"],
        "is_manual": written_record["verification_method"] == "manual",
        "operation": operation,
        "operation_id": operation_id,
        "previous_status": old_status,
        "modified_by": teacher_id,
        "modified_at": datetime.now(UTC).isoformat(),
        "summary": summary,
    }

