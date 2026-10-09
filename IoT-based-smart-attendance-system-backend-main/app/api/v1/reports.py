"""Reports router — student and session reports."""

from __future__ import annotations

import io
import re
from typing import Literal

from fastapi import APIRouter, Query
from fastapi.responses import StreamingResponse

from app.api.deps import TeacherUser
from app.core.exceptions import AppError
from app.schemas.reports import (
    SessionReportDetail,
    SessionReportPaginatedResponse,
    StudentAttendanceReport,
)
from app.services import report_export_service, report_service

router = APIRouter(prefix="/reports", tags=["reports"])


def sanitize_filename(name: str) -> str:
    """Replace characters that are invalid in filenames with underscores."""
    return re.sub(r'[\\/*?:"<>|]', "_", name)


@router.get("/students", response_model=list[StudentAttendanceReport])
@router.get("/students/", response_model=list[StudentAttendanceReport], include_in_schema=False)
async def get_student_reports(
    user: TeacherUser,
    search: str | None = Query(None, description="Search by student name or roll number"),
    category: Literal["all", "normal", "warning", "critical"] = Query(
        "all", description="Filter by compliance risk category"
    ),
) -> list[dict]:
    """Retrieve student attendance summary analytics reports.

    Teacher role is required; students receive HTTP 403 Forbidden.
    """
    return report_service.get_student_reports(search=search, category=category)


@router.get("/sessions", response_model=SessionReportPaginatedResponse)
async def get_completed_sessions_report(
    user: TeacherUser,
    page: int = Query(1, ge=1, description="Page number"),
    page_size: int = Query(20, ge=1, le=100, description="Items per page"),
    search: str | None = Query(None, description="Search by subject, classroom, or teacher"),
) -> dict:
    """Retrieve paginated completed session summaries with statistics.

    Teacher role is required; students receive HTTP 403 Forbidden.
    """
    return report_service.get_completed_sessions_report(
        page=page, page_size=page_size, search=search
    )


@router.get("/session/{session_id}", response_model=SessionReportDetail)
async def get_session_detail_report(
    session_id: str,
    user: TeacherUser,
) -> dict:
    """Retrieve full compliance detail report for a specific completed session.

    Teacher role is required; students receive HTTP 403 Forbidden.
    """
    return report_service.get_session_detail_report(session_id)


@router.get("/session/{session_id}/export")
async def export_session_report(
    session_id: str,
    user: TeacherUser,
    format: str = Query("xlsx", description="Export format (xlsx only)"),
) -> StreamingResponse:
    """Export detailed session compliance report as a spreadsheet.

    Teacher role is required; students receive HTTP 403 Forbidden.
    Only 'xlsx' format is supported (HTTP 400 otherwise).
    """
    if format != "xlsx":
        raise AppError(
            message=f"Unsupported export format '{format}'. Only 'xlsx' is supported.",
            code="BAD_REQUEST",
            status_code=400,
        )

    # 1. Fetch raw detail data (throws 404 NotFoundError if unknown session)
    detail_report = report_service.get_session_detail_report(session_id)

    # 2. Build workbook
    try:
        wb = report_export_service.build_session_report_workbook(detail_report)
    except Exception as exc:
        raise AppError(
            message=f"Unexpected workbook generation failure: {exc}",
            code="INTERNAL_SERVER_ERROR",
            status_code=500,
        ) from exc


    # 3. Derive dynamic filename: <subject_name>_<YYYY-MM-DD>.xlsx
    session_data = detail_report.get("session") or {}
    subject_name = session_data.get("subject_name")
    started_at = session_data.get("started_at")

    filename = None
    if subject_name and started_at:
        try:
            date_str = started_at.split("T")[0]
            sanitized_subject = sanitize_filename(subject_name)
            filename = f"{sanitized_subject}_{date_str}.xlsx"
        except Exception:
            pass

    if not filename:
        filename = f"session_report_{session_id}.xlsx"

    # 4. Stream response
    stream = io.BytesIO()
    wb.save(stream)
    stream.seek(0)

    return StreamingResponse(
        stream,
        media_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        headers={"Content-Disposition": f'attachment; filename="{filename}"'},
    )
