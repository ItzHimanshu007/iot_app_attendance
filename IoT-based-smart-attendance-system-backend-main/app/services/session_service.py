"""Session service — create, close, query, and auto-expire attendance sessions.

Business rules enforced:
  1. Classroom must exist
  2. Only one active session per classroom
  3. Session expiration calculated by backend
  4. MQTT commands sent on start/stop
  5. Token generated and distributed on session start
  6. Tokens rotated automatically every TOKEN_ROTATION_INTERVAL_SECONDS

Migration 0002 changes (subject_name):
  * create_session() accepts subject_name (str) instead of subject_id.
  * Subject existence validation removed — teachers type any subject name.
  * Timetable ownership check removed — any authenticated teacher can open a
    session in any available classroom.
  * _resolve_subject_name() provides backward-compatible name resolution for
    old sessions that still carry subject_id but no subject_name.
"""

from __future__ import annotations

import traceback
from datetime import UTC, datetime, timedelta
from typing import Any

from app.core.exceptions import (
    AuthorizationError,
    ConflictError,
    NotFoundError,
    SessionNotActiveError,
)
from app.core.logging import get_logger
from app.mqtt.publisher import (
    publish_start_session,
    publish_stop_session,
    publish_token_update,
)
from app.repositories.classroom_repo import ClassroomRepository
from app.repositories.enrollment_repo import EnrollmentRepository
from app.repositories.session_repo import SessionRepository
from app.repositories.subject_repo import SubjectRepository
from app.repositories.timetable_repo import TimetableRepository
from app.schemas.session import SessionContext
from app.services import notification_service
from app.services.token_service import FIXED_TOKEN_MODE, generate_session_token

logger = get_logger(__name__)

_session_repo = SessionRepository()
_subject_repo = SubjectRepository()  # kept for historical-session name lookup only
_classroom_repo = ClassroomRepository()
_enrollment_repo = EnrollmentRepository()
_timetable_repo = TimetableRepository()


# ── Private helpers ───────────────────────────────────────────────────────────


def _resolve_subject_name(session: dict[str, Any]) -> str:
    """Return a display name for *any* session regardless of schema generation.

    Resolution order (migration 0002 backward-compat):
      1. session["subject_name"] — set on all sessions created after 0002.
      2. Look up subjects table via session["subject_id"] — historical rows.
      3. "Unknown Subject" — subject record has been deleted.
    """
    if session.get("subject_name"):
        return session["subject_name"]

    subject_id = session.get("subject_id")
    if subject_id:
        subject = _subject_repo.get_by_id(subject_id)
        if subject:
            return subject["name"]

    return "Unknown Subject"


# ── Public API ────────────────────────────────────────────────────────────────


def create_session(
    teacher_id: str,
    subject_name: str,
    classroom_id: str,
    duration_minutes: int = 60,
    notes: str | None = None,
    timetable_id: str | None = None,
    user_role: str = "teacher",
) -> dict[str, Any]:
    """Create an attendance session and broadcast start command via MQTT.

    Supports both Flow A (Scheduled Session via timetable_id) and Flow B
    (Custom Session).
    """
    resolved_classroom_id = classroom_id
    resolved_subject_id = None
    resolved_subject_name = subject_name

    if timetable_id:
        # Load the timetable slot
        timetable = _timetable_repo.get_by_id(timetable_id)
        if not timetable:
            raise ConflictError(f"Timetable slot '{timetable_id}' not found")

        # Validate timetable is active
        if "is_active" in timetable and timetable.get("is_active") is False:
            raise ConflictError(f"Timetable slot '{timetable_id}' is inactive")

        # Validate subject_id exists in timetable
        subject_id = timetable.get("subject_id")
        if not subject_id:
            raise ConflictError(f"Timetable slot '{timetable_id}' has no associated subject_id")

        # Validate classroom_id exists in timetable
        timetable_classroom_id = timetable.get("classroom_id")
        if not timetable_classroom_id:
            raise ConflictError(f"Timetable slot '{timetable_id}' has no associated classroom_id")

        # Single source of truth: ignore client-supplied classroom_id, use resolved one from timetable
        resolved_classroom_id = timetable_classroom_id

        # Validate classroom record exists
        timetable_classroom = _classroom_repo.get_by_id(resolved_classroom_id)
        if not timetable_classroom:
            raise ConflictError(f"Classroom '{resolved_classroom_id}' associated with timetable slot not found")

        # Validate subject record exists
        subject = _subject_repo.get_by_id(subject_id)
        if not subject:
            raise ConflictError(f"Subject '{subject_id}' associated with timetable slot not found")

        # Verify teacher ownership (admins bypass this check)
        if user_role != "admin" and timetable.get("teacher_id") != teacher_id:
            raise AuthorizationError("You do not have permission to use this timetable slot")

        # Prevent duplicate ACTIVE sessions for this timetable_id
        active_timetable_session = _session_repo.get_active_by_timetable(timetable_id)
        if active_timetable_session:
            raise ConflictError("An active attendance session already exists for this timetable.")

        # Resolved subject_id and snapshot subject name
        resolved_subject_id = subject_id
        resolved_subject_name = (subject.get("name") if subject else timetable.get("subject_name")) or subject_name

    # Validate classroom exists
    classroom = _classroom_repo.get_by_id(resolved_classroom_id)
    if not classroom:
        raise NotFoundError("Classroom", resolved_classroom_id)

    # Check no active session in this classroom
    active = _session_repo.get_active_by_classroom(resolved_classroom_id)
    if active:
        raise ConflictError(
            f"An active session already exists in classroom '{classroom['name']}'"
            f" (session: {active['id']})"
        )

    # 3. Calculate expiration
    now = datetime.now(UTC)
    expires_at = now + timedelta(minutes=duration_minutes)

    # 4. Generate initial beacon token
    token = generate_session_token(resolved_classroom_id)

    # 5. Insert session
    data: dict[str, Any] = {
        "teacher_id": teacher_id,
        "subject_name": resolved_subject_name,
        "classroom_id": resolved_classroom_id,
        "status": "active",
        "started_at": now.isoformat(),
        "expires_at": expires_at.isoformat(),
        "duration_minutes": duration_minutes,
        "current_token": token,
        "token_rotated_at": now.isoformat(),
        "total_present": 0,
        "timetable_id": timetable_id,
        "subject_id": resolved_subject_id,
    }
    if notes:
        data["notes"] = notes

    session = _session_repo.insert(data)
    logger.info(
        "Session created",
        session_id=session["id"],
        teacher_id=teacher_id,
        subject_name=resolved_subject_name,
        classroom_id=resolved_classroom_id,
    )

    # 6. Send MQTT start command to ESP32 devices
    logger.info(
        "Preparing START_SESSION publish",
        session_id=session["id"],
        classroom_id=resolved_classroom_id,
        duration_minutes=duration_minutes,
        token_prefix=token[:6] + "…",
    )
    try:
        publish_start_session(resolved_classroom_id, session["id"], token, duration_minutes)
        logger.info(
            "START_SESSION publish completed",
            topic=f"campus/classroom/{resolved_classroom_id}/control/start",
            session_id=session["id"],
            classroom_id=resolved_classroom_id,
        )
    except Exception as e:
        logger.error(
            "START_SESSION publish FAILED",
            exception_type=type(e).__name__,
            exception_message=str(e),
            session_id=session["id"],
            classroom_id=resolved_classroom_id,
            stack_trace=traceback.format_exc(),
        )

    # 7. Notify enrolled students (best-effort; new sessions have no subject_id
    #    so the enrollment lookup returns an empty list — no exception raised)
    try:
        notification_service.send_session_started(
            [], session["id"], subject_name, classroom["name"]
        )
    except Exception as e:
        logger.error("Failed to send session start notifications", error=str(e))

    return session


def close_session(session_id: str, teacher_id: str) -> dict[str, Any]:
    """End an active session and broadcast stop command via MQTT.

    Raises:
        NotFoundError:       Session not found.
        SessionNotActiveError: Session is not in active state.
        AuthorizationError:  Teacher doesn't own this session.
    """
    session = _session_repo.get_by_id(session_id)
    if not session:
        raise NotFoundError("AttendanceSession", session_id)

    if session["status"] != "active":
        raise SessionNotActiveError(session_id)

    if session["teacher_id"] != teacher_id:
        raise AuthorizationError("You can only close your own sessions")

    # Close the session
    updated = _session_repo.close_session(session_id)
    logger.info("Session closed", session_id=session_id, teacher_id=teacher_id)

    # Send MQTT stop command
    try:
        publish_stop_session(session["classroom_id"], session_id)
    except Exception as e:
        logger.error("Failed to publish MQTT stop command", error=str(e))

    # Notify students — resolve display name via backward-compat helper
    try:
        display_name = _resolve_subject_name(session)
        # For old sessions we can still look up enrolled students; for new
        # sessions subject_id is NULL so get_subject_students returns [].
        subject_id = session.get("subject_id")
        student_ids: list[str] = []
        if subject_id:
            enrolled = _enrollment_repo.get_subject_students(subject_id)
            student_ids = [e["student_id"] for e in enrolled]
        notification_service.send_session_ended(student_ids, session_id, display_name)
    except Exception as e:
        logger.error("Failed to send session end notifications", error=str(e))

    return updated


def get_session(session_id: str) -> dict[str, Any]:
    """Get a session by ID.

    Raises:
        NotFoundError: Session not found.
    """
    session = _session_repo.get_by_id(session_id)
    if not session:
        raise NotFoundError("AttendanceSession", session_id)
    # Inject resolved subject_name so callers always receive a human-readable
    # name regardless of which schema generation created the session.
    if not session.get("subject_name"):
        session = dict(session)
        session["subject_name"] = _resolve_subject_name(session)
    return session


def get_active_session(classroom_id: str) -> dict[str, Any] | None:
    """Get the currently active session in a classroom (or None)."""
    return _session_repo.get_active_by_classroom(classroom_id)


def get_session_status(session_id: str) -> dict[str, Any]:
    """Get session status with computed fields.

    Raises:
        NotFoundError: Session not found.
    """
    session = get_session(session_id)
    now = datetime.now(UTC)
    expires_at = datetime.fromisoformat(session["expires_at"])

    is_expired = now >= expires_at and session["status"] == "active"
    remaining_seconds = max(0, int((expires_at - now).total_seconds()))

    return {
        **session,
        "is_expired": is_expired,
        "remaining_seconds": remaining_seconds,
    }


def list_teacher_sessions(teacher_id: str, limit: int = 50) -> list[dict[str, Any]]:
    """List all sessions for a teacher."""
    return _session_repo.list_by_teacher(teacher_id, limit=limit)


def list_subject_sessions(subject_id: str, limit: int = 50) -> list[dict[str, Any]]:
    """List all sessions for a subject (legacy — uses subject_id FK)."""
    return _session_repo.list_by_subject(subject_id, limit=limit)


def get_any_active_session() -> dict[str, Any] | None:
    """Return the first currently active session (any classroom).

    Used by the mock token source — student discovers a running session
    without knowing the classroom ID in advance.  Returns None when no
    active session exists anywhere in the system.

    FIXED_TOKEN_MODE = True (current):
      Returns the session as-is with its stored current_token.
      Token was generated once at creation and does not rotate.

    FIXED_TOKEN_MODE = False (future — MQTT rotation enabled):
      Regenerates a fresh HMAC token for the current time window and
      persists it so Flutter always receives a token valid right now.
      FUTURE_WORK: remove the FIXED_TOKEN_MODE guard below when MQTT sync
      is operational and set FIXED_TOKEN_MODE = False in token_service.py.
    """
    session = _session_repo.get_any_active()
    if session is None:
        return None

    if FIXED_TOKEN_MODE:
        # Development mode — return stored token unchanged, no rotation.
        logger.info(
            "get_any_active_session: returning stored token (fixed-token mode)",
            session_id=session["id"],
            classroom_id=session["classroom_id"],
        )
        return session

    # Production mode — regenerate a fresh token for the current time window.
    # FUTURE_WORK: restore this block when MQTT sync is implemented.
    classroom_id = session["classroom_id"]
    fresh_token = generate_session_token(classroom_id)
    updated = _session_repo.update_token(session["id"], fresh_token)

    logger.info(
        "get_any_active_session: refreshed token",
        session_id=session["id"],
        classroom_id=classroom_id,
        token_prefix=fresh_token[:6] + "…",
    )

    return updated


def rotate_token(session_id: str, teacher_id: str) -> dict[str, Any]:
    """Generate a new beacon token for an active session.

    FIXED_TOKEN_MODE = True (current):
      Returns the session's existing stored token without generating a new
      one.  Manual rotation is a no-op in dev mode because the ESP32
      firmware token cannot be updated without MQTT.

    FIXED_TOKEN_MODE = False (future — MQTT rotation enabled):
      Generates a fresh HMAC token, stores it, and publishes it via MQTT
      so the ESP32 can update its advertisement.
      FUTURE_WORK: remove the FIXED_TOKEN_MODE guard below.

    Raises:
        NotFoundError: Session not found.
        SessionNotActiveError: Session is not active.
        AuthorizationError: Teacher doesn't own this session.
    """
    session = _session_repo.get_by_id(session_id)
    if not session:
        raise NotFoundError("AttendanceSession", session_id)

    if session["status"] != "active":
        raise SessionNotActiveError(session_id)

    if session["teacher_id"] != teacher_id:
        raise AuthorizationError("You can only rotate tokens for your own sessions")

    if FIXED_TOKEN_MODE:
        # Development mode — return the stored token unchanged.
        # FUTURE_WORK: remove this block when MQTT sync is operational.
        logger.info(
            "rotate_token: no-op in fixed-token mode",
            session_id=session_id,
        )
        return {
            "session_id": session_id,
            "token": session.get("current_token", ""),
            "classroom_id": session["classroom_id"],
            "fixed_token_mode": True,
        }

    # Production mode — delegate to shared core (no logic duplication).
    return _rotate_session(session_id, session["classroom_id"])


def auto_expire_sessions() -> int:
    """Find and close all active sessions past their expiration.

    Called by a background task. Returns the number of sessions expired.
    """
    expired = _session_repo.list_expired_active()
    count = 0
    for session in expired:
        try:
            _session_repo.close_session(session["id"])
            publish_stop_session(session["classroom_id"], session["id"])
            count += 1
            logger.info("Session auto-expired", session_id=session["id"])
        except Exception as e:
            logger.error(
                "Failed to auto-expire session",
                session_id=session["id"],
                error=str(e),
            )
    if count > 0:
        logger.info("Auto-expire sweep complete", expired_count=count)
    return count


# ── Private rotation core ─────────────────────────────────────────────────────


def _rotate_session(session_id: str, classroom_id: str) -> dict[str, Any]:
    """Generate a new HMAC token, persist it, and publish it via MQTT.

    This is the single source of token-rotation logic shared by:
      * rotate_token()              — manual teacher API endpoint
      * rotate_all_active_sessions() — automatic scheduler

    Caller is responsible for all authorisation and pre-condition checks
    (session exists, is active, caller has permission, FIXED_TOKEN_MODE guard).
    """
    new_token = generate_session_token(classroom_id)
    _session_repo.update_token(session_id, new_token)
    logger.info(
        "Rotated session token",
        session_id=session_id,
        classroom_id=classroom_id,
        token_prefix=new_token[:4] + "...",
    )
    try:
        publish_token_update(classroom_id, session_id, new_token)
        logger.info(
            "Published rotated token",
            topic=f"campus/classroom/{classroom_id}/token",
            session_id=session_id,
        )
    except Exception as e:
        logger.error(
            "Failed to publish token rotation",
            session_id=session_id,
            classroom_id=classroom_id,
            error=str(e),
        )
    return {
        "session_id": session_id,
        "token": new_token,
        "classroom_id": classroom_id,
    }


# ── Automatic rotation scheduler entry-point ──────────────────────────────────


def rotate_all_active_sessions() -> int:
    """Rotate beacon tokens for every active, non-expired session.

    Called by the background rotation task in main.py every
    TOKEN_ROTATION_INTERVAL_SECONDS seconds.

    * Respects FIXED_TOKEN_MODE — returns 0 immediately when True.
    * Skips sessions whose expires_at has already passed (the expiry
      sweep will close them on its next pass).
    * Isolates failures per session — one classroom failing does not
      prevent the remaining classrooms from being rotated.

    Returns:
        Number of sessions successfully rotated in this sweep.
    """
    if FIXED_TOKEN_MODE:
        return 0

    sessions = _session_repo.get_all_active()
    now = datetime.now(UTC)
    rotated = 0

    for session in sessions:
        session_id = session["id"]
        classroom_id = session["classroom_id"]
        try:
            # Skip sessions already past their wall-clock expiry.
            # The expiry sweep closes them; no point pushing a new token.
            expires_at = datetime.fromisoformat(session["expires_at"])
            if now >= expires_at:
                logger.debug(
                    "Skipping expired session in rotation sweep",
                    session_id=session_id,
                    classroom_id=classroom_id,
                )
                continue

            _rotate_session(session_id, classroom_id)
            rotated += 1

        except Exception as e:
            logger.error(
                "Rotation failed",
                session_id=session_id,
                classroom_id=classroom_id,
                reason=str(e),
            )

    return rotated


def _resolve_subject_id(session: dict[str, Any], raise_on_error: bool = True) -> str | None:
    """Resolve the subject ID for a session.

    Priority resolution chain:
    1. Timetable-based resolution: using timetable_id to lookup in timetables.
    2. Direct resolution: using subject_id on the session itself.
    3. Fallback name-matching: searching subjects by name/code.

    Raises:
        ConflictError: If subject_id cannot be resolved.
    """
    # 1. Timetable-based resolution
    timetable_id = session.get("timetable_id")
    if timetable_id:
        timetable = _timetable_repo.get_by_id(timetable_id)
        if timetable and timetable.get("subject_id"):
            logger.info(
                "Resolved subject ID via timetable",
                session_id=session["id"],
                timetable_id=timetable_id,
                subject_id=timetable["subject_id"],
            )
            return timetable["subject_id"]

    # 2. Direct resolution (historical sessions)
    subject_id = session.get("subject_id")
    if subject_id:
        logger.info(
            "Resolved subject ID directly from session record",
            session_id=session["id"],
            subject_id=subject_id,
        )
        return subject_id

    # 3. Fallback name-matching
    # TODO: [Fallback] Compatibility check using subject_name. Remove once all sessions are tied to timetables or subjects.
    subject_name = session.get("subject_name")
    if subject_name:
        logger.warning(
            "Attempting fallback subject resolution by name matching",
            session_id=session["id"],
            subject_name=subject_name,
        )
        subject = _subject_repo.get_by_name(subject_name)
        if subject:
            logger.warning(
                "Successfully resolved subject ID via fallback name matching",
                session_id=session["id"],
                subject_name=subject_name,
                subject_id=subject["id"],
            )
            return subject["id"]

    if not raise_on_error:
        logger.warning(
            "Roster resolution warning: could not determine subject ID for session. Returning None.",
            session_id=session["id"],
            subject_name=subject_name,
        )
        return None

    logger.error(
        "Roster resolution failure: could not determine subject ID for session",
        session_id=session["id"],
        timetable_id=timetable_id,
        subject_id=subject_id,
        subject_name=subject_name,
    )
    raise ConflictError(f"Could not resolve subject roster for session '{session['id']}'")



def validate_roster_access(session_id: str, current_user_id: str, user_role: str) -> SessionContext:
    """Validate that the session exists and authorize the user context.

    If the user is a teacher, verifies they own the session.
    If subject resolution fails, raises ConflictError (409).

    Returns:
        SessionContext: Strongly typed validated session context.
    """
    session = _session_repo.get_by_id(session_id)
    if not session:
        raise NotFoundError("AttendanceSession", session_id)

    # Validate teacher ownership / admin authorization
    if user_role != "admin" and session.get("teacher_id") != current_user_id:
        raise AuthorizationError("You do not have access to this session's roster")

    classroom_id = session["classroom_id"]
    classroom = _classroom_repo.get_by_id(classroom_id)
    if not classroom:
        raise NotFoundError("Classroom", classroom_id)

    # Resolve subject_id (returns None if resolution fails and raise_on_error is False)
    resolved_subject_id = _resolve_subject_id(session, raise_on_error=False)

    # Construct strongly typed SessionContext
    # We resolve the display subject name via our backward-compat helper
    # because session["subject_name"] might be null for legacy sessions.
    display_subject_name = _resolve_subject_name(session)

    return SessionContext(
        session_id=session["id"],
        teacher_id=session["teacher_id"],
        classroom_id=session["classroom_id"],
        subject_name=display_subject_name,
        session_status=session["status"],
        started_at=datetime.fromisoformat(session["started_at"]),
        classroom_name=classroom["name"],
        resolved_subject_id=resolved_subject_id,
    )
