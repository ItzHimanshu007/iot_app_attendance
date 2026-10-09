"""``attendance_attempts`` table — audit of every verification attempt."""

from __future__ import annotations

from typing import Any

from app.db.base_repository import BaseRepository


class AttemptRepository(BaseRepository):
    """Attendance attempts (successes and failures)."""

    table_name = "attendance_attempts"

    def list_attempts(
        self,
        since: str,
        until: str,
        success: bool | None = None,
        staff_id: str | None = None,
        limit: int = 200,
    ) -> list[dict[str, Any]]:
        """Attempts in a time range, newest first."""
        query = self.table.select("*").gte("created_at", since).lt("created_at", until)
        if success is not None:
            query = query.eq("success", success)
        if staff_id:
            query = query.eq("staff_id", staff_id)
        return self._rows(query.order("created_at", desc=True).limit(limit), "list")
