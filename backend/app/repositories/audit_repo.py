"""``admin_audit_log`` table — every admin action."""

from __future__ import annotations

from typing import Any

from app.db.base_repository import BaseRepository


class AuditRepository(BaseRepository):
    """Admin audit log."""

    table_name = "admin_audit_log"

    def recent(self, limit: int = 100) -> list[dict[str, Any]]:
        """Most recent admin actions."""
        return self._rows(
            self.table.select("*").order("created_at", desc=True).limit(limit), "recent"
        )
