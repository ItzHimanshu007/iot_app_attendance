"""Classroom repository."""

from __future__ import annotations

from typing import Any

from app.repositories.base import BaseRepository


class ClassroomRepository(BaseRepository):
    table_name = "classrooms"

    def list_by_building(self, building: str) -> list[dict[str, Any]]:
        return self._safe_execute(
            self.table.select("*").eq("building", building).eq("is_active", True).order("name"),
            operation="list_by_building",
        )

    def list_active(self) -> list[dict[str, Any]]:
        return self._safe_execute(
            self.table.select("*").eq("is_active", True).order("building").order("name"),
            operation="list_active",
        )
