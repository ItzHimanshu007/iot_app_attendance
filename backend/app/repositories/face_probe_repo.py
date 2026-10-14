"""``face_probes`` table — recent live face signatures, for replay detection."""

from __future__ import annotations

from app.db.base_repository import BaseRepository


class FaceProbeRepository(BaseRepository):
    """Signatures from accepted check-ins/outs (never photos)."""

    table_name = "face_probes"

    def recent(self, staff_id: str, limit: int) -> list[list[float]]:
        """The staff member's latest probe signatures, newest first."""
        rows = self._rows(
            self.table.select("embedding")
            .eq("staff_id", staff_id)
            .order("created_at", desc=True)
            .limit(limit),
            "recent",
        )
        return [r["embedding"] for r in rows if r.get("embedding")]

    def add(self, staff_id: str, embedding: list[float]) -> None:
        """Remember one accepted probe."""
        self._write(
            self.table.insert({"staff_id": staff_id, "embedding": embedding}),
            "add",
        )
