"""Manual attendance audit repository."""

from __future__ import annotations

from app.repositories.base import BaseRepository


class ManualAttendanceAuditRepository(BaseRepository):
    table_name = "manual_attendance_audits"
