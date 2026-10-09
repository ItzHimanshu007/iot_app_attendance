"""``attendance_challenges`` table — one-time nonces."""

from __future__ import annotations

from typing import Any

from app.db.base_repository import BaseRepository


class ChallengeRepository(BaseRepository):
    """Attendance challenges."""

    table_name = "attendance_challenges"

    def consume(self, challenge_id: str, staff_id: str, at: str) -> dict[str, Any] | None:
        """Atomically mark a challenge as used.

        Returns the row if THIS call consumed it, or None if it does not exist,
        belongs to someone else, or was already consumed (replay).
        """
        rows = self._rows(
            self.table.update({"consumed_at": at})
            .eq("id", challenge_id)
            .eq("staff_id", staff_id)
            .is_("consumed_at", "null"),
            "consume",
        )
        return rows[0] if rows else None
