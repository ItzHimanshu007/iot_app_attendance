"""Notification repository."""

from __future__ import annotations

from datetime import UTC, datetime
from typing import Any

from app.repositories.base import BaseRepository


class NotificationRepository(BaseRepository):
    table_name = "notifications"

    def list_for_user(
        self,
        user_id: str,
        unread_only: bool = False,
        limit: int = 50,
    ) -> list[dict[str, Any]]:
        """Notifications for a user, including system-wide broadcasts."""
        query = self.table.select("*")
        # user's own notifications OR system broadcasts (recipient_id IS NULL)
        query = query.or_(f"recipient_id.eq.{user_id},recipient_id.is.null")
        if unread_only:
            query = query.eq("is_read", False)
        return self._safe_execute(
            query.order("created_at", desc=True).limit(limit),
            operation="list_for_user",
        )

    def unread_count(self, user_id: str) -> int:
        """Count unread notifications for a user."""
        query = (
            self._db.table(self.table_name)
            .select("id", count="exact")
            .eq("recipient_id", user_id)
            .eq("is_read", False)
        )
        try:
            resp = query.execute()
        except Exception as exc:
            from app.repositories.base import RepositoryError

            raise RepositoryError(
                f"Count query failed: {exc}",
                table=self.table_name,
                operation="unread_count",
            ) from exc

        if resp is None:
            from app.repositories.base import RepositoryError

            raise RepositoryError(
                "Supabase returned None on count",
                table=self.table_name,
                operation="unread_count",
            )
        return resp.count or 0

    def mark_read(self, notification_id: str, user_id: str) -> dict[str, Any] | None:
        """Mark a notification as read (only if it belongs to the user)."""
        now = datetime.now(UTC).isoformat()
        rows = self._safe_execute(
            self.table.update({"is_read": True, "read_at": now})
            .eq("id", notification_id)
            .eq("recipient_id", user_id),
            operation="mark_read",
        )
        return rows[0] if rows else None

    def mark_all_read(self, user_id: str) -> int:
        """Mark all notifications for a user as read. Returns count updated."""
        now = datetime.now(UTC).isoformat()
        rows = self._safe_execute(
            self.table.update({"is_read": True, "read_at": now})
            .eq("recipient_id", user_id)
            .eq("is_read", False),
            operation="mark_all_read",
        )
        return len(rows)
