"""``beacons`` table — ESP32 BLE beacons."""

from __future__ import annotations

from typing import Any

from app.db.base_repository import BaseRepository


class BeaconRepository(BaseRepository):
    """Campus beacons."""

    table_name = "beacons"

    def list_beacons(self) -> list[dict[str, Any]]:
        """All beacons, newest first."""
        return self._rows(self.table.select("*").order("created_at", desc=True), "list")
