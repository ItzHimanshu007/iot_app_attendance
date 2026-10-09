"""``staff`` table — one profile per Supabase auth user."""

from __future__ import annotations

from typing import Any

from app.db.base_repository import BaseRepository


class StaffRepository(BaseRepository):
    """Staff profiles."""

    table_name = "staff"

    def list_staff(self, status: str | None = None, limit: int = 500) -> list[dict[str, Any]]:
        """List staff ordered by name, optionally filtered by status."""
        query = self.table.select("*")
        if status:
            query = query.eq("status", status)
        return self._rows(query.order("full_name").limit(limit), "list")

    def list_active(self) -> list[dict[str, Any]]:
        """All active staff (used for the daily roster)."""
        return self.list_staff(status="active", limit=5000)
