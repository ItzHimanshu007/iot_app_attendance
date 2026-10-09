"""Attendance record repository."""

from __future__ import annotations

from typing import Any

from app.core.logging import get_logger
from app.repositories.base import BaseRepository, RepositoryError

logger = get_logger(__name__)


class AttendanceRepository(BaseRepository):
    table_name = "attendance_records"

    def has_marked(self, session_id: str, student_id: str) -> bool:
        """Check if a student already has a record for this session."""
        rows = self._safe_execute(
            self.table.select("id")
            .eq("session_id", session_id)
            .eq("student_id", student_id)
            .limit(1),
            operation="has_marked",
        )
        return bool(rows)

    def list_by_session(self, session_id: str, limit: int = 200) -> list[dict[str, Any]]:
        """All attendance records for a session including student profile details."""
        return self._safe_execute(
            self.table.select("*, student:users(*)")
            .eq("session_id", session_id)
            .order("marked_at", desc=False)
            .limit(limit),
            operation="list_by_session",
        )

    def list_by_student(self, student_id: str, limit: int = 100) -> list[dict[str, Any]]:
        """Attendance history for a student across all sessions including student profile details."""
        return self._safe_execute(
            self.table.select("*, student:users(*)")
            .eq("student_id", student_id)
            .order("marked_at", desc=True)
            .limit(limit),
            operation="list_by_student",
        )

    def get_by_id_with_profile(self, record_id: str) -> dict[str, Any] | None:
        """Fetch a single attendance record by ID, joining with the student's profile details."""
        return self._safe_single(
            self.table.select("*, student:users(*)")
            .eq("id", record_id)
            .maybe_single(),
            operation="get_by_id_with_profile",
        )


    def count_by_session(self, session_id: str) -> int:
        """Count present students for a session."""
        return self.count({"session_id": session_id, "status": "present"})

    def revoke(self, record_id: str, reason: str) -> dict[str, Any]:
        """Revoke an attendance record."""
        return self.update(
            record_id,
            {"status": "revoked", "rejection_reason": reason},
        )

    def get_by_session_and_student(self, session_id: str, student_id: str) -> dict[str, Any] | None:
        """Fetch attendance record for a student in a session."""
        return self._safe_single(
            self.table.select("*")
            .eq("session_id", session_id)
            .eq("student_id", student_id)
            .maybe_single(),
            operation="get_by_session_and_student",
        )

    def update_with_concurrency_check(
        self, record_id: str, data: dict[str, Any], last_updated_at: str
    ) -> dict[str, Any]:
        """Update record only if updated_at matches last_updated_at to prevent concurrent modifications."""
        return self._safe_write(
            self.table.update(data).eq("id", record_id).eq("updated_at", last_updated_at),
            operation="update_with_concurrency_check",
        )

    def get_session_present_count(self, session_id: str) -> int:
        """Count present/late records for a session."""
        query = (
            self._db.table(self.table_name)
            .select("id", count="exact")
            .eq("session_id", session_id)
            .in_("status", ["present", "late"])
        )
        try:
            resp = query.execute()
        except Exception as exc:
            logger.error("Failed to query present count", error=str(exc))
            raise RepositoryError(
                f"Query failed: {exc}", table=self.table_name, operation="get_session_present_count"
            )
        if resp is None:
            return 0
        return resp.count or 0

    def list_by_sessions(self, session_ids: list[str]) -> list[dict[str, Any]]:
        """List all attendance records for a list of session IDs."""
        if not session_ids:
            return []
        return self._safe_execute(
            self.table.select("student_id, session_id, status, verification_method, marked_at").in_(
                "session_id", session_ids
            ),
            operation="list_by_sessions",
        )


