"""Attendance schemas — request/response DTOs for attendance marking."""

from __future__ import annotations

from datetime import datetime
from typing import Literal

from pydantic import BaseModel, Field


class AttendanceMark(BaseModel):
    """Request body to mark attendance — includes all anti-fraud fields."""

    session_id: str
    beacon_token: str
    ble_rssi: int | None = Field(default=None, ge=-127, le=0)
    biometric_verified: bool = False
    device_fingerprint: str


class AttendanceResponse(BaseModel):
    """Response body for an attendance record."""

    id: str
    session_id: str
    student_id: str
    status: str
    verification_method: str
    biometric_verified: bool
    ble_rssi: int | None = None
    marked_at: datetime
    verified_at: datetime | None = None
    rejection_reason: str | None = None
    created_at: datetime

    # Profile & presentation fields
    student_name: str | None = None
    roll_number: str | None = None
    attendance_status: str | None = None
    is_manual: bool = False



class ManualAttendanceMark(BaseModel):
    """Request schema for manually marking/changing attendance status."""

    session_id: str
    student_id: str
    status: Literal["present", "late", "absent"]
    reason: str | None = None


class RosterSummary(BaseModel):
    """Summary statistics for session roster."""

    total_students: int
    present: int
    absent: int


class ManualAttendanceResponse(BaseModel):
    """Response schema representing the manual attendance mark outcome."""

    id: str
    session_id: str
    student_id: str
    status: str
    verification_method: str
    biometric_verified: bool
    ble_rssi: int | None = None
    marked_at: datetime
    verified_at: datetime | None = None
    rejection_reason: str | None = None
    created_at: datetime

    # Profile & presentation fields
    student_name: str | None = None
    roll_number: str | None = None
    attendance_status: str | None = None
    is_manual: bool = False

    # Hardening & correlation fields
    operation: Literal["created", "updated", "unchanged"]
    operation_id: str
    previous_status: str | None = None
    modified_by: str
    modified_at: datetime
    summary: RosterSummary

