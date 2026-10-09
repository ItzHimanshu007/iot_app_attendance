"""Attendance router — mark and query attendance records."""

from __future__ import annotations

from fastapi import APIRouter, Request

from app.api.deps import AuthenticatedUser, StudentUser, TeacherUser
from app.schemas.attendance import (
    AttendanceMark,
    AttendanceResponse,
    ManualAttendanceMark,
    ManualAttendanceResponse,
)
from app.services import attendance_service

router = APIRouter(prefix="/attendance", tags=["attendance"])


@router.post("/", response_model=AttendanceResponse, status_code=201)
async def mark_attendance(body: AttendanceMark, user: StudentUser, request: Request) -> dict:
    """Mark attendance for an active session.

    Requires student role. Executes the full 8-step validation engine.
    """
    ip = request.client.host if request.client else None
    return attendance_service.submit_attendance(
        student_id=user.id,
        session_id=body.session_id,
        beacon_token=body.beacon_token,
        device_fingerprint=body.device_fingerprint,
        biometric_verified=body.biometric_verified,
        ble_rssi=body.ble_rssi,
        ip_address=ip,
    )


@router.get("/session/{session_id}", response_model=list[AttendanceResponse])
async def list_session_attendance(session_id: str, user: TeacherUser) -> list[dict]:
    """List all attendance records for a session. Requires teacher role."""
    return attendance_service.list_session_attendance(session_id)


@router.get("/me", response_model=list[AttendanceResponse])
async def my_attendance(user: StudentUser) -> list[dict]:
    """Get the current student's attendance history."""
    return attendance_service.list_student_attendance(user.id)


@router.get("/{record_id}", response_model=AttendanceResponse)
async def get_attendance_record(record_id: str, user: AuthenticatedUser) -> dict:
    """Get a single attendance record by ID."""
    return attendance_service.get_attendance_record(record_id)


@router.patch("/{record_id}/revoke")
async def revoke_attendance(record_id: str, reason: str, user: TeacherUser) -> dict:
    """Revoke an attendance record. Requires teacher or admin role."""
    return attendance_service.revoke_attendance(record_id, reason)


@router.post("/manual", response_model=ManualAttendanceResponse, status_code=200)
async def mark_manual_attendance(body: ManualAttendanceMark, user: TeacherUser) -> dict:
    """Manually mark/change attendance status for a student.

    Requires teacher or admin role. Teachers can only modify their own sessions.
    """
    return attendance_service.mark_manual_attendance(
        session_id=body.session_id,
        student_id=body.student_id,
        status=body.status,
        teacher_id=user.id,
        user_role=user.role,
        reason=body.reason,
    )
