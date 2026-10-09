"""ESP32 device repository."""

from __future__ import annotations

from datetime import UTC, datetime
from typing import Any

from app.repositories.base import BaseRepository


class Esp32Repository(BaseRepository):
    table_name = "esp32_devices"

    def get_by_classroom(self, classroom_id: str) -> list[dict[str, Any]]:
        """All active ESP32 devices in a classroom."""
        return self._safe_execute(
            self.table.select("*").eq("classroom_id", classroom_id).eq("is_active", True),
            operation="get_by_classroom",
        )

    def update_heartbeat(self, mqtt_client_id: str, wifi_rssi: int | None = None) -> None:
        """Update heartbeat timestamp and WiFi RSSI."""
        now = datetime.now(UTC).isoformat()
        data: dict[str, Any] = {
            "last_heartbeat_at": now,
            "status": "online",
        }
        if wifi_rssi is not None:
            data["wifi_rssi"] = wifi_rssi
        self.table.update(data).eq("mqtt_client_id", mqtt_client_id).execute()

    def set_status(self, device_id: str, status: str) -> dict[str, Any]:
        return self.update(device_id, {"status": status})

    def list_stale(self, threshold_minutes: int = 5) -> list[dict[str, Any]]:
        """Devices that haven't sent a heartbeat within the threshold."""
        from datetime import timedelta

        cutoff = (datetime.now(UTC) - timedelta(minutes=threshold_minutes)).isoformat()
        return self._safe_execute(
            self.table.select("*")
            .eq("is_active", True)
            .eq("status", "online")
            .lt("last_heartbeat_at", cutoff),
            operation="list_stale",
        )
