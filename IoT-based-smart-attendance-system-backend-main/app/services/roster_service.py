"""Roster service — fetches, aggregates, and builds attendance session rosters."""

from __future__ import annotations

import math
import re
from datetime import datetime
from typing import Any

from app.core.logging import get_logger
from app.repositories.attendance_repo import AttendanceRepository
from app.repositories.enrollment_repo import EnrollmentRepository
from app.schemas.session import (
    PaginationMetadata,
    RosterStudent,
    SessionContext,
    SessionRosterHeader,
    SessionRosterResponse,
    SessionRosterSummary,
)

logger = get_logger(__name__)

_enrollment_repo = EnrollmentRepository()
_attendance_repo = AttendanceRepository()


def _natural_sort_key(s: str | None) -> list[Any]:
    """Helper for natural sorting of alphanumeric roll numbers. Places None at the end."""
    if s is None:
        return [1, ""]
    return [0, [int(c) if c.isdigit() else c.lower() for c in re.split(r"(\d+)", s)]]


def get_session_roster(
    context: SessionContext,
    page: int = 1,
    page_size: int = 100,
    sort: str = "roll",
) -> dict[str, Any]:
    """Fetch the consolidated roster and attendance status for a session.

    Performs exactly 2 bulk database queries to avoid N+1 issues:
      1. Fetch enrollments for the resolved subject ID (including student profiles).
      2. Fetch attendance records for the session ID.
    Merges them in memory and returns a sorted, paginated response model.
    """
    logger.info(
        "Building session roster",
        session_id=context.session_id,
        resolved_subject_id=context.resolved_subject_id,
        page=page,
        page_size=page_size,
        sort=sort,
    )

    # 1. Fetch enrolled students with profiles in bulk
    if context.resolved_subject_id:
        enrollments = _enrollment_repo.get_subject_students_with_profiles(context.resolved_subject_id)
    else:
        enrollments = []

    # 2. Fetch session attendance records in bulk
    attendance_records = _attendance_repo.list_by_session(context.session_id, limit=1000)

    # 3. Map attendance records by student_id for O(1) lookup
    record_map = {r["student_id"]: r for r in attendance_records}

    # 4. Merge datasets and build RosterStudent objects
    roster_students: list[RosterStudent] = []
    if enrollments:
        for item in enrollments:
            student = item.get("student")
            # Ensure student user profile exists and is active
            if student and student.get("is_active", False):
                student_id = student["id"]
                roll_number = student.get("student_id_number")
                full_name = student["full_name"]

                # Map attendance record if present
                record = record_map.get(student_id)
                is_manual = False
                if record:
                    status = record.get("status", "present")
                    marked_at_str = record.get("marked_at")
                    marked_at = datetime.fromisoformat(marked_at_str) if marked_at_str else None
                    is_manual = record.get("verification_method") == "manual"
                else:
                    status = "absent"
                    marked_at = None

                roster_students.append(
                    RosterStudent(
                        student_id=student_id,
                        roll_number=roll_number,
                        full_name=full_name,
                        attendance_status=status,
                        marked_at=marked_at,
                        is_manual=is_manual,
                    )
                )
    else:
        # Fallback flow for custom sessions: build roster from actual attendance records
        for record in attendance_records:
            student = record.get("student")
            if student and student.get("is_active", False):
                student_id = student["id"]
                roll_number = student.get("student_id_number")
                full_name = student["full_name"]
                status = record.get("status", "present")
                marked_at_str = record.get("marked_at")
                marked_at = datetime.fromisoformat(marked_at_str) if marked_at_str else None
                is_manual = record.get("verification_method") == "manual"

                roster_students.append(
                    RosterStudent(
                        student_id=student_id,
                        roll_number=roll_number,
                        full_name=full_name,
                        attendance_status=status,
                        marked_at=marked_at,
                        is_manual=is_manual,
                    )
                )


    # 5. Sort students based on sort parameter
    if sort == "name":
        roster_students.sort(key=lambda s: s.full_name.lower())
    else:  # sort == "roll"
        roster_students.sort(key=lambda s: _natural_sort_key(s.roll_number))

    # 6. Compute summary statistics (calculated on total roster before pagination)
    total_students = len(roster_students)
    present_count = sum(1 for s in roster_students if s.attendance_status in ("present", "late"))
    absent_count = sum(1 for s in roster_students if s.attendance_status in ("absent", "revoked"))

    # 7. Apply pagination
    total_pages = math.ceil(total_students / page_size) if total_students > 0 else 0
    start_idx = (page - 1) * page_size
    end_idx = start_idx + page_size
    paginated_students = roster_students[start_idx:end_idx]

    response = SessionRosterResponse(
        session=SessionRosterHeader(
            id=context.session_id,
            subject_name=context.subject_name,
            classroom_name=context.classroom_name,
            status=context.session_status,
        ),
        summary=SessionRosterSummary(
            total_students=total_students,
            present=present_count,
            absent=absent_count,
        ),
        pagination=PaginationMetadata(
            page=page,
            page_size=page_size,
            total_students=total_students,
            total_pages=total_pages,
        ),
        students=paginated_students,
    )

    return response.model_dump()
