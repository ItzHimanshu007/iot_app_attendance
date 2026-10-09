"""Registered device repository."""

from __future__ import annotations

from datetime import UTC, datetime
from typing import Any

from app.repositories.base import BaseRepository


class DeviceRepository(BaseRepository):
    table_name = "registered_devices"

    def get_active_by_user(self, user_id: str) -> dict[str, Any] | None:
        """Get the active registered device for a user."""
        return self._safe_single(
            self.table.select("*").eq("user_id", user_id).eq("is_active", True).maybe_single(),
            operation="get_active_by_user",
        )

    def get_by_fingerprint(self, fingerprint: str) -> dict[str, Any] | None:
        """Look up a device by its unique fingerprint."""
        return self._safe_single(
            self.table.select("*").eq("device_fingerprint", fingerprint).maybe_single(),
            operation="get_by_fingerprint",
        )

    def deactivate_user_devices(self, user_id: str, reason: str) -> None:
        """Deactivate all active devices for a user."""
        now = datetime.now(UTC).isoformat()
        self.table.update(
            {
                "is_active": False,
                "deactivated_at": now,
                "deactivation_reason": reason,
            }
        ).eq("user_id", user_id).eq("is_active", True).execute()

    def touch_last_active(self, device_id: str) -> None:
        """Update last_active_at timestamp."""
        now = datetime.now(UTC).isoformat()
        self.table.update({"last_active_at": now}).eq("id", device_id).execute()

    def reactivate(self, device_id: str) -> dict[str, Any]:
        """Reactivate a previously deactivated device.

        Sets is_active = True, clears deactivation metadata, and
        refreshes last_active_at.  Used when the same user re-registers
        a device that was deactivated by a prior replacement.
        """
        now = datetime.now(UTC).isoformat()
        return self._safe_write(
            self.table.update(
                {
                    "is_active": True,
                    "deactivated_at": None,
                    "deactivation_reason": None,
                    "last_active_at": now,
                }
            )
            .eq("id", device_id)
            .eq("is_active", False),
            operation="reactivate",
        )

    def get_history_by_user(self, user_id: str) -> list[dict[str, Any]]:
        """All devices (active + deactivated) for a user."""
        return self._safe_execute(
            self.table.select("*").eq("user_id", user_id).order("created_at", desc=True),
            operation="get_history_by_user",
        )
