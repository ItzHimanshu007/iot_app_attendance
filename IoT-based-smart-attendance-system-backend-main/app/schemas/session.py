"""Session schemas — request/response DTOs for the attendance sessions router."""

from __future__ import annotations

from datetime import datetime

from pydantic import BaseModel, Field, field_validator

from app.core.constants import ALLOWED_SESSION_DURATIONS, ALLOWED_SESSION_DURATIONS_MSG


class SessionCreate(BaseModel):
    """Request body to create a new attendance session.

    ``subject_name`` replaces the old ``subject_id`` field (migration 0002).
    Teachers type the subject name freely; the backend stores it as-is after
    trimming surrounding whitespace.

    ``duration_minutes`` must be one of the values in ALLOWED_SESSION_DURATIONS
    to match the discrete options offered by the Flutter UI exactly.
    """

    subject_name: str = Field(
        ...,
        min_length=3,
        max_length=100,
        description=(
            "Human-readable subject name entered by the teacher, "
            "e.g. 'Operating Systems' or 'IoT Lab'."
        ),
    )
    classroom_id: str
    # No range constraint on the Field itself — the validator below enforces
    # the discrete allow-list.  A bare `int` type is used so that the 422
    # body clearly attributes the error to the custom validator message rather
    # than a range constraint.
    duration_minutes: int = Field(
        default=60,
        description=ALLOWED_SESSION_DURATIONS_MSG,
    )
    notes: str | None = None
    timetable_id: str | None = None

    @field_validator("subject_name", mode="before")
    @classmethod
    def strip_and_reject_blank(cls, v: object) -> str:
        """Trim surrounding whitespace and reject strings that become empty."""
        if not isinstance(v, str):
            raise ValueError("subject_name must be a string")
        v = v.strip()
        if not v:
            raise ValueError("subject_name must not be blank or whitespace-only")
        return v

    @field_validator("duration_minutes", mode="after")
    @classmethod
    def must_be_allowed_duration(cls, v: int) -> int:
        """Reject any duration not in the Flutter UI allow-list."""
        if v not in ALLOWED_SESSION_DURATIONS:
            raise ValueError(ALLOWED_SESSION_DURATIONS_MSG)
        return v


class SessionResponse(BaseModel):
    """Response body for an attendance session.

    Backward-compatible with sessions created before migration 0002:
    * New sessions  → subject_name is set, subject_id is None.
    * Old sessions  → subject_id is set, subject_name is None.
    Both fields are always present in the response (one will be None).
    """

    id: str
    timetable_id: str | None = None
    teacher_id: str
    # subject_id kept for backward-compat; None for sessions created after
    # migration 0002.
    subject_id: str | None = None
    # Free-text subject name; None for historical sessions (resolved in the
    # service layer via the subjects table fallback before returning).
    subject_name: str | None = None
    classroom_id: str
    status: str
    started_at: datetime
    expires_at: datetime
    ended_at: datetime | None = None
    duration_minutes: int
    total_present: int = 0
    notes: str | None = None
    created_at: datetime
    # Token fields — required by Flutter MockAttendanceTokenSource to build
    # a valid AttendanceSessionAdvertisement without BLE hardware.
    current_token: str | None = None
    token_rotated_at: datetime | None = None


class SessionEnd(BaseModel):
    """Response body after ending a session."""

    session_id: str
    status: str
    total_present: int


class SessionContext(BaseModel):
    """Lightweight strongly typed context representing a validated attendance session."""

    session_id: str
    teacher_id: str
    classroom_id: str
    subject_name: str
    session_status: str
    started_at: datetime
    classroom_name: str
    resolved_subject_id: str | None = None


class SessionRosterHeader(BaseModel):
    """Basic session metadata for the roster response."""

    id: str
    subject_name: str
    classroom_name: str
    status: str


class SessionRosterSummary(BaseModel):
    """Summary counts for the attendance session roster."""

    total_students: int
    present: int
    absent: int


class RosterStudent(BaseModel):
    """Information representing a single student and their attendance status in a roster."""

    student_id: str
    roll_number: str | None = None
    full_name: str
    attendance_status: str  # "present", "late", "absent", "revoked"
    marked_at: datetime | None = None
    is_manual: bool = False


class PaginationMetadata(BaseModel):
    """Metadata regarding paginated results."""

    page: int
    page_size: int
    total_students: int
    total_pages: int


class SessionRosterResponse(BaseModel):
    """Consolidated API response containing header, statistics, pagination, and student rosters."""

    session: SessionRosterHeader
    summary: SessionRosterSummary
    pagination: PaginationMetadata
    students: list[RosterStudent]
