"""Attendance session repository."""

from __future__ import annotations

from datetime import UTC, datetime
from typing import Any

from app.repositories.base import BaseRepository


class SessionRepository(BaseRepository):
    table_name = "attendance_sessions"

    def get_active_by_classroom(self, classroom_id: str) -> dict[str, Any] | None:
        """Get the currently active session in a classroom (if any).

        Returns:
            Session dict if an active session exists, None if the classroom
            is free.  Never raises AttributeError / TypeError.

        Raises:
            RepositoryError: On Supabase connection failure or unexpected
                response.
        """
        return self._safe_single(
            self.table.select("*")
            .eq("classroom_id", classroom_id)
            .eq("status", "active")
            .maybe_single(),
            operation="get_active_by_classroom",
        )

    def get_active_by_teacher(self, teacher_id: str) -> list[dict[str, Any]]:
        """All active sessions for a teacher."""
        return self._safe_execute(
            self.table.select("*")
            .eq("teacher_id", teacher_id)
            .eq("status", "active")
            .order("started_at", desc=True),
            operation="get_active_by_teacher",
        )

    def list_by_teacher(self, teacher_id: str, limit: int = 50) -> list[dict[str, Any]]:
        return self._safe_execute(
            self.table.select("*")
            .eq("teacher_id", teacher_id)
            .order("started_at", desc=True)
            .limit(limit),
            operation="list_by_teacher",
        )

    def list_by_subject(self, subject_id: str, limit: int = 50) -> list[dict[str, Any]]:
        return self._safe_execute(
            self.table.select("*")
            .eq("subject_id", subject_id)
            .order("started_at", desc=True)
            .limit(limit),
            operation="list_by_subject",
        )

    def list_expired_active(self) -> list[dict[str, Any]]:
        """Find active sessions past their expiration time (for auto-expire sweep)."""
        now = datetime.now(UTC).isoformat()
        return self._safe_execute(
            self.table.select("*").eq("status", "active").lt("expires_at", now),
            operation="list_expired_active",
        )

    def get_any_active(self) -> dict[str, Any] | None:
        """Return the first active session across all classrooms.

        Used by the mock token source so students can discover any running
        session without knowing the classroom ID in advance.
        Returns None if no active session exists.
        """
        results = self._safe_execute(
            self.table.select("*").eq("status", "active").order("started_at", desc=True).limit(1),
            operation="get_any_active",
        )
        return results[0] if results else None

    def get_all_active(self) -> list[dict[str, Any]]:
        """Return every session currently in 'active' status across all classrooms.

        Used by the automatic token rotation scheduler to iterate over every
        classroom that needs a fresh beacon token each rotation interval.
        """
        return self._safe_execute(
            self.table.select("*").eq("status", "active").order("started_at", desc=True),
            operation="get_all_active",
        )

    def close_session(self, session_id: str) -> dict[str, Any]:
        """Mark a session as completed."""
        now = datetime.now(UTC).isoformat()
        return self.update(
            session_id,
            {"status": "completed", "ended_at": now},
        )

    def cancel_session(self, session_id: str) -> dict[str, Any]:
        """Mark a session as cancelled."""
        now = datetime.now(UTC).isoformat()
        return self.update(
            session_id,
            {"status": "cancelled", "ended_at": now},
        )

    def update_token(self, session_id: str, token: str) -> dict[str, Any]:
        """Store the current beacon token and rotation timestamp."""
        now = datetime.now(UTC).isoformat()
        return self.update(
            session_id,
            {"current_token": token, "token_rotated_at": now},
        )

    def increment_present(self, session_id: str, current_count: int = 0) -> None:
        """Atomically increment the denormalized present count at the database level.

        Uses a raw SQL update so concurrent attendance submissions cannot
        overwrite each other (both reading count=5 and writing 6 instead of 7).

        The `current_count` parameter is kept for backwards-compat but is not used.
        """
        self._db.rpc(
            "increment_session_present",
            {"p_session_id": session_id},
        ).execute()

    def get_active_by_timetable(self, timetable_id: str) -> dict[str, Any] | None:
        """Find an active session linked to the given timetable slot.

        Returns:
            Session dict if found, None otherwise.
        """
        return self._safe_single(
            self.table.select("*")
            .eq("timetable_id", timetable_id)
            .eq("status", "active")
            .maybe_single(),
            operation="get_active_by_timetable",
        )

    def list_sessions_for_date(self, target_date: str) -> list[dict[str, Any]]:
        """List all sessions started on a specific date (YYYY-MM-DD)."""
        start = f"{target_date}T00:00:00+00:00"
        end = f"{target_date}T23:59:59+00:00"
        return self._safe_execute(
            self.table.select("*")
            .gte("started_at", start)
            .lte("started_at", end),
            operation="list_sessions_for_date",
        )

    def list_completed(self) -> list[dict[str, Any]]:
        """List all completed sessions with subject, classroom, and teacher names joined."""
        return self._safe_execute(
            self.table.select(
                "id, subject_id, subject_name, classroom_id, started_at, "
                "ended_at, teacher_id, status, "
                "classroom:classrooms(name), teacher:users(full_name), "
                "subject:subjects(name)"
            ).eq("status", "completed"),
            operation="list_completed",
        )

    def get_completed_with_relations(self, session_id: str) -> dict[str, Any] | None:
        """Fetch a single completed session with joined relations."""
        return self._safe_single(
            self.table.select(
                "id, subject_id, subject_name, classroom_id, started_at, "
                "ended_at, teacher_id, status, "
                "classroom:classrooms(name), teacher:users(full_name), "
                "subject:subjects(name)"
            )
            .eq("id", session_id)
            .eq("status", "completed")
            .maybe_single(),
            operation="get_completed_with_relations",
        )



