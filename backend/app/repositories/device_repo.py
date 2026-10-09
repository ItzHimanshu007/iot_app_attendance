"""``devices`` table — the phone bound to each staff member."""

from __future__ import annotations

from typing import Any

from app.db.base_repository import BaseRepository


class DeviceRepository(BaseRepository):
    """Bound devices."""

    table_name = "devices"

    def get_active_by_staff(self, staff_id: str) -> dict[str, Any] | None:
        """The staff member's active device, if any."""
        rows = self._rows(
            self.table.select("*").eq("staff_id", staff_id).eq("is_active", True).limit(1),
            "get_active_by_staff",
        )
        return rows[0] if rows else None

    def get_active_by_fingerprint(self, fingerprint: str) -> dict[str, Any] | None:
        """The active device row that owns this fingerprint, if any."""
        rows = self._rows(
            self.table.select("*")
            .eq("device_fingerprint", fingerprint)
            .eq("is_active", True)
            .limit(1),
            "get_active_by_fingerprint",
        )
        return rows[0] if rows else None

    def list_active(self) -> list[dict[str, Any]]:
        """All active devices (admin staff list)."""
        return self._rows(self.table.select("*").eq("is_active", True), "list_active")

    def deactivate_for_staff(self, staff_id: str, reason: str, at: str) -> list[dict[str, Any]]:
        """Deactivate every active device of a staff member."""
        return self._rows(
            self.table.update(
                {"is_active": False, "deactivated_at": at, "deactivation_reason": reason}
            )
            .eq("staff_id", staff_id)
            .eq("is_active", True),
            "deactivate_for_staff",
        )
