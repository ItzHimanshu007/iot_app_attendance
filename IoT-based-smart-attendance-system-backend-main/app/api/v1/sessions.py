"""Sessions router — create, query, and close attendance sessions."""

from __future__ import annotations

from datetime import UTC, datetime
from typing import Literal

from fastapi import APIRouter, Query

from app.api.deps import AuthenticatedUser, TeacherUser
from app.schemas.session import SessionCreate, SessionEnd, SessionResponse, SessionRosterResponse
from app.services import roster_service, session_service

router = APIRouter(prefix="/sessions", tags=["sessions"])


@router.post("/", response_model=SessionResponse, status_code=201)
async def create_session(body: SessionCreate, user: TeacherUser) -> dict:
    """Create an attendance session and broadcast start via MQTT.

    Requires teacher role.  The teacher enters any subject name they choose;
    no predefined subject UUID is needed (migration 0002).
    """
    return session_service.create_session(
        teacher_id=user.id,
        subject_name=body.subject_name,
        classroom_id=body.classroom_id,
        duration_minutes=body.duration_minutes,
        notes=body.notes,
        timetable_id=body.timetable_id,
        user_role=user.role,
    )


@router.get("/", response_model=list[SessionResponse])
async def list_sessions(user: TeacherUser) -> list[dict]:
    """List all sessions for the current teacher."""
    return session_service.list_teacher_sessions(user.id)


@router.get("/active", response_model=SessionResponse | None)
async def get_active_session(classroom_id: str, user: AuthenticatedUser) -> dict | None:
    """Get the currently active session for a classroom (null if none).

    Used by the Flutter student app to resolve a BLE classroomId into a
    live session_id before submitting attendance. Returns 200 with null
    body when no active session exists — never 404.
    """
    return session_service.get_active_session(classroom_id)


@router.get("/current-active", response_model=SessionResponse | None)
async def get_current_active_session(user: AuthenticatedUser) -> dict | None:
    """Return the first currently active session (any classroom).

    Used by the Flutter mock token source so students can discover a running
    session without knowing the classroom ID in advance.  Returns null when
    no active session exists anywhere in the system.

    Teacher: returns their own active session (most recently started).
    Student / other: returns the globally first active session.
    """
    return session_service.get_any_active_session()


@router.get("/{session_id}", response_model=SessionResponse)
async def get_session(session_id: str, user: AuthenticatedUser) -> dict:
    """Fetch a single session by ID."""
    return session_service.get_session(session_id)


@router.get("/{session_id}/status")
async def get_session_status(session_id: str, user: AuthenticatedUser) -> dict:
    """Get session status with remaining time."""
    return session_service.get_session_status(session_id)


@router.patch("/{session_id}/end", response_model=SessionEnd)
async def end_session(session_id: str, user: TeacherUser) -> dict:
    """Mark a session as completed and broadcast stop via MQTT."""
    result = session_service.close_session(session_id, user.id)
    return {
        "session_id": result["id"],
        "status": result["status"],
        "total_present": result["total_present"],
    }


@router.post("/{session_id}/rotate-token")
async def rotate_token(session_id: str, user: TeacherUser) -> dict:
    """Force a beacon token rotation for an active session.

    Generates a new HMAC token, updates DB, and publishes via MQTT
    so ESP32 devices update their BLE advertisement.

    Response keys match Flutter TokenRotationResult.fromJson():
      new_token   → token string (Flutter reads 'new_token')
      rotated_at  → ISO timestamp of rotation
      session_id  → echoed back for correlation
      classroom_id → for ESP32 topic routing
    """
    result = session_service.rotate_token(session_id, user.id)
    return {
        "session_id": result["session_id"],
        "new_token": result["token"],
        "rotated_at": datetime.now(UTC).isoformat(),
        "classroom_id": result["classroom_id"],
    }


@router.get("/{session_id}/roster", response_model=SessionRosterResponse)
async def get_session_roster(
    session_id: str,
    user: TeacherUser,
    page: int = Query(default=1, ge=1),
    page_size: int = Query(default=100, ge=10, le=200),
    sort: Literal["roll", "name"] = "roll",
) -> dict:
    """Fetch the consolidated roster and attendance status for a session.

    Requires teacher or admin role. Teachers can only query sessions they own.
    """
    # 1. Validate session, permissions, and resolve subject ID via SessionService
    context = session_service.validate_roster_access(
        session_id=session_id,
        current_user_id=user.id,
        user_role=user.role,
    )

    # 2. Build and map roster via RosterService
    return roster_service.get_session_roster(context, page=page, page_size=page_size, sort=sort)
