"""Reports schemas — student and session report DTOs."""

from __future__ import annotations

from typing import Literal

from pydantic import BaseModel, Field


class StudentAttendanceReport(BaseModel):
    """Response schema representing a student's attendance summary analytics."""

    student_id: str = Field(description="Unique identifier of the student")
    roll_number: str | None = Field(None, description="Student's roll number / ID number")
    student_name: str = Field(description="Student's full name")
    total_sessions: int = Field(
        description="Number of completed sessions the student was expected to attend"
    )
    sessions_attended: int = Field(
        description="Number of sessions attended (present or late)"
    )
    sessions_missed: int = Field(
        description="Number of sessions missed (absent, revoked, or unregistered)"
    )
    attendance_rate: float = Field(
        description="Attendance percentage rate as a decimal value between 0.0 and 1.0"
    )
    category: Literal["normal", "warning", "critical"] = Field(
        description="Attendance compliance risk level category"
    )


class SessionReportSummary(BaseModel):
    """Summary of a completed session for the Reports list."""

    session_id: str = Field(description="Unique identifier of the session")
    subject_id: str | None = Field(None, description="Identifier of the subject")
    subject_name: str = Field(description="Resolved display name of the subject")
    classroom_id: str = Field(description="Identifier of the classroom")
    classroom_name: str = Field(description="Resolved display name of the classroom")
    started_at: str = Field(description="ISO timestamp when the session started")
    completed_at: str | None = Field(None, description="ISO timestamp when the session ended")
    present_count: int = Field(description="Number of students marked present")
    late_count: int = Field(description="Number of students marked late")
    absent_count: int = Field(description="Number of students marked/inferred absent")
    manual_count: int = Field(description="Number of manually marked attendance records")
    total_students: int = Field(description="Total count of students expected or registered")
    teacher_name: str = Field(description="Display name of the presiding teacher")


class SessionReportHeader(BaseModel):
    """Metadata header for a specific completed session."""

    session_id: str = Field(description="Unique identifier of the session")
    subject_name: str = Field(description="Resolved display name of the subject")
    classroom_name: str = Field(description="Resolved display name of the classroom")
    teacher_name: str = Field(description="Display name of the presiding teacher")
    started_at: str = Field(description="ISO timestamp when the session started")
    completed_at: str | None = Field(None, description="ISO timestamp when the session ended")


class SessionReportSummaryStats(BaseModel):
    """Aggregate statistics for a completed session."""

    present_count: int = Field(description="Number of students marked present")
    late_count: int = Field(description="Number of students marked late")
    absent_count: int = Field(description="Number of students marked/inferred absent")
    manual_count: int = Field(description="Number of manually marked attendance records")
    total_students: int = Field(description="Total count of students expected or registered")


class StudentSessionRow(BaseModel):
    """Spreadsheet-compatible row representation for a student's attendance in a session."""

    student_id: str = Field(description="Unique identifier of the student")
    roll_number: str | None = Field(None, description="Student's roll number / ID number")
    student_name: str = Field(description="Student's full name")
    attendance_status: Literal["present", "late", "absent", "revoked"] = Field(
        description="Resolved attendance status"
    )
    verification_method: Literal["automatic", "manual"] | None = Field(
        None, description="Verification method: automatic, manual, or None (absent)"
    )
    marked_at: str | None = Field(None, description="ISO timestamp of attendance mark or None")


class SessionReportDetail(BaseModel):
    """Full detail report for a completed session, matching Flutter UI hierarchy."""

    session: SessionReportHeader = Field(description="Session metadata header details")
    summary: SessionReportSummaryStats = Field(description="Session summary statistics")
    students: list[StudentSessionRow] = Field(description="List of individual student rows")


class SessionReportPaginatedResponse(BaseModel):
    """Paginated response containing completed session reports."""

    items: list[SessionReportSummary] = Field(description="Completed session report summaries")
    total: int = Field(description="Total number of matching completed sessions")
    page: int = Field(description="Current page number")
    page_size: int = Field(description="Number of items per page")
    total_pages: int = Field(description="Total number of pages available")
