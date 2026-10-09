"""``face_templates`` table — enrolled face signatures (no images)."""

from __future__ import annotations

from typing import Any

from app.db.base_repository import BaseRepository


class FaceTemplateRepository(BaseRepository):
    """Face templates, keyed by ``staff_id``."""

    table_name = "face_templates"

    def get(self, staff_id: str) -> dict[str, Any] | None:
        """Template for one staff member."""
        return self._one(self.table.select("*").eq("staff_id", staff_id).maybe_single(), "get")

    def upsert(self, data: dict[str, Any]) -> dict[str, Any]:
        """Create or replace a staff member's template."""
        return self._write(self.table.upsert(data, on_conflict="staff_id"), "upsert")

    def update_status(self, staff_id: str, data: dict[str, Any]) -> dict[str, Any]:
        """Update status/review fields."""
        return self._write(self.table.update(data).eq("staff_id", staff_id), "update_status")

    def delete(self, staff_id: str) -> None:
        """Remove a template."""
        self._rows(self.table.delete().eq("staff_id", staff_id), "delete")

    def list_approved(self) -> list[dict[str, Any]]:
        """Every approved template (duplicate-face check)."""
        return self._rows(
            self.table.select("staff_id, embeddings").eq("status", "approved"), "list_approved"
        )

    def list_status(self) -> list[dict[str, Any]]:
        """Status of every template without the (large) embeddings."""
        return self._rows(
            self.table.select("staff_id, status, sample_count, model_version, updated_at"),
            "list_status",
        )
