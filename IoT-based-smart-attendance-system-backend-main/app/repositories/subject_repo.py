"""Subject repository."""

from __future__ import annotations

from typing import Any

from app.repositories.base import BaseRepository


class SubjectRepository(BaseRepository):
    table_name = "subjects"

    def get_by_code(self, code: str) -> dict[str, Any] | None:
        return self._safe_single(
            self.table.select("*").eq("code", code).maybe_single(),
            operation="get_by_code",
        )

    def list_active(self, department: str | None = None) -> list[dict[str, Any]]:
        query = self.table.select("*").eq("is_active", True)
        if department:
            query = query.eq("department", department)
        return self._safe_execute(query.order("code"), operation="list_active")

    def get_by_name(self, name: str) -> dict[str, Any] | None:
        """Find a subject by name (case-insensitive fallback)."""
        return self._safe_single(
            self.table.select("*").ilike("name", name).limit(1).maybe_single(),
            operation="get_by_name",
        )
