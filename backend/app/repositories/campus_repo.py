"""``campus_settings`` table — single configuration row (id = 1)."""

from __future__ import annotations

from typing import Any

from app.db.base_repository import BaseRepository


class CampusSettingsRepository(BaseRepository):
    """Campus configuration."""

    table_name = "campus_settings"

    def get(self) -> dict[str, Any] | None:
        """The settings row."""
        return self.get_by_id(1)  # type: ignore[arg-type]

    def save(self, data: dict[str, Any]) -> dict[str, Any]:
        """Update the settings row."""
        return self._write(self.table.update(data).eq("id", 1), "save")
