"""``attendance`` table — one row per staff member per day."""

from __future__ import annotations

from typing import Any

from app.db.base_repository import BaseRepository


class AttendanceRepository(BaseRepository):
    """Daily attendance records."""

    table_name = "attendance"

    def get_for_day(self, staff_id: str, day: str) -> dict[str, Any] | None:
        """A staff member's record for one date (YYYY-MM-DD)."""
        rows = self._rows(
            self.table.select("*").eq("staff_id", staff_id).eq("attendance_date", day).limit(1),
            "get_for_day",
        )
        return rows[0] if rows else None

    def list_for_staff(
        self, staff_id: str, date_from: str, date_to: str, limit: int = 120
    ) -> list[dict[str, Any]]:
        """A staff member's records in a date range, newest first."""
        return self._rows(
            self.table.select("*")
            .eq("staff_id", staff_id)
            .gte("attendance_date", date_from)
            .lte("attendance_date", date_to)
            .order("attendance_date", desc=True)
            .limit(limit),
            "list_for_staff",
        )

    def list_range(self, date_from: str, date_to: str) -> list[dict[str, Any]]:
        """Every record in a date range (roster / export)."""
        return self._rows(
            self.table.select("*")
            .gte("attendance_date", date_from)
            .lte("attendance_date", date_to)
            .order("attendance_date")
            .limit(100000),
            "list_range",
        )
